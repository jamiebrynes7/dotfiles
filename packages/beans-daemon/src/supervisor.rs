use crate::registry::{ProjectState, Registry};
use crate::spawner::{ChildHandle, ChildSpawner};
use async_trait::async_trait;
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

pub struct Supervisor<S: ChildSpawner> {
    pub registry: Arc<Mutex<Registry>>,
    pub spawner: S,
    /// Health-check timeout for child startup.
    pub health_timeout: Duration,
    /// Live child handles, keyed by project path. Held so the supervisor
    /// can SIGTERM/SIGKILL them later (eviction, restart, shutdown).
    pub children: Arc<Mutex<HashMap<std::path::PathBuf, Box<dyn ChildHandle>>>>,
}

impl<S: ChildSpawner + 'static> Supervisor<S> {
    /// Spawn a child for `key`, wait for health, transition registry state.
    /// Caller is responsible for having already inserted a `Spawning` entry
    /// for the key (so the cap accounting is correct from cd-op's POV).
    pub async fn start_project(&self, key: std::path::PathBuf) -> anyhow::Result<()> {
        let port = crate::port_alloc::pick_loopback_port()?;
        let child = self.spawner.spawn(&key, port).await?;
        let pid = child.pid();
        let spawned_at = Instant::now();
        self.children.lock().await.insert(key.clone(), child);

        if Self::wait_until_healthy(port, self.health_timeout).await {
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Healthy {
                    port,
                    pid,
                    spawned_at,
                },
            )?;
        } else {
            if let Some(mut c) = self.children.lock().await.remove(&key) {
                let _ = c.send_sigkill().await;
            }
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Dead {
                    reason: "startup health check timed out".into(),
                    since: Instant::now(),
                },
            )?;
        }
        Ok(())
    }

    /// Store a child handle under `key`. Used by the supervisor itself and
    /// by tests that want to seed the children map without going through
    /// `start_project`.
    pub async fn insert_child(&self, key: std::path::PathBuf, child: Box<dyn ChildHandle>) {
        self.children.lock().await.insert(key, child);
    }

    /// Wrapper around `start_project` that retries up to `max_attempts` times
    /// with `base_backoff * 4^n` delay between attempts (1s, 4s, 16s for default 1s).
    pub async fn start_project_with_retries(
        &self,
        key: std::path::PathBuf,
        max_attempts: usize,
        base_backoff: Duration,
    ) -> anyhow::Result<()> {
        let mut backoff = base_backoff;
        for attempt in 0..max_attempts {
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Spawning {
                    since: Instant::now(),
                },
            )?;
            self.start_project(key.clone()).await?;
            let healthy = matches!(
                self.registry.lock().await.get(&key).map(|p| &p.state),
                Some(ProjectState::Healthy { .. })
            );
            if healthy {
                return Ok(());
            }
            if attempt + 1 < max_attempts {
                tracing::warn!(?key, attempt = attempt + 1, ?backoff, "child startup failed; backing off");
                tokio::time::sleep(backoff).await;
                backoff *= 4;
            }
        }
        // Final start_project already left state = Dead; nothing more to do.
        Ok(())
    }

    /// Begin eviction of `key`: pulls its child handle, transitions registry
    /// to `Evicting`, then spawns a background task running `evict`.
    /// Fire-and-forget: callers do not await completion.
    pub fn trigger_eviction(
        self: &Arc<Self>,
        key: std::path::PathBuf,
        sigterm_grace: Duration,
        sigkill_grace: Duration,
    ) {
        let me = self.clone();
        tokio::spawn(async move {
            let child = me.children.lock().await.remove(&key);
            match child {
                Some(child) => {
                    me.registry
                        .lock()
                        .await
                        .transition_state(
                            &key,
                            ProjectState::Evicting {
                                since: Instant::now(),
                            },
                        )
                        .ok();
                    Self::evict(me.registry.clone(), key, child, sigterm_grace, sigkill_grace)
                        .await;
                }
                None => {
                    tracing::warn!(?key, "trigger_eviction: no child handle stored");
                    me.registry.lock().await.remove(&key);
                }
            }
        });
    }

    async fn wait_until_healthy(port: u16, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;
        let url = format!("http://127.0.0.1:{port}/");
        loop {
            if Instant::now() >= deadline {
                return false;
            }
            if let Ok(resp) = reqwest::get(&url).await {
                if resp.status().is_success() {
                    return true;
                }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }

    /// Background task: SIGTERM → wait → SIGKILL → wait → drop entry.
    /// Logs WARN on reap timeout (orphaned process).
    pub async fn evict(
        registry: Arc<Mutex<Registry>>,
        key: std::path::PathBuf,
        mut child: Box<dyn ChildHandle>,
        sigterm_grace: Duration,
        sigkill_grace: Duration,
    ) {
        let pid = child.pid();
        tracing::info!(?key, pid, "evicting project");

        let _ = child.send_sigterm().await;
        if tokio::time::timeout(sigterm_grace, child.wait()).await.is_ok() {
            registry.lock().await.remove(&key);
            tracing::info!(?key, pid, "evicted (clean SIGTERM exit)");
            return;
        }

        let _ = child.send_sigkill().await;
        if tokio::time::timeout(sigkill_grace, child.wait()).await.is_ok() {
            registry.lock().await.remove(&key);
            tracing::info!(?key, pid, "evicted (SIGKILL)");
            return;
        }

        registry.lock().await.remove(&key);
        tracing::warn!(
            ?key,
            pid,
            "eviction reap timed out; orphaning process — bounded RAM cost until reboot"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    /// Mock spawner that immediately starts an in-process axum responding 200.
    struct ImmediateHealthySpawner;
    #[async_trait]
    impl ChildSpawner for ImmediateHealthySpawner {
        async fn spawn(&self, _dir: &Path, port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
            let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
            tokio::spawn(async move {
                use axum::routing::get;
                let app = axum::Router::new().route("/", get(|| async { "ok" }));
                axum::serve(listener, app).await.ok();
            });
            Ok(Box::new(MockChild { pid: 12345 }))
        }
    }

    struct MockChild {
        pid: u32,
    }
    #[async_trait]
    impl ChildHandle for MockChild {
        fn pid(&self) -> u32 {
            self.pid
        }
        async fn wait(&mut self) -> std::io::Result<String> {
            std::future::pending().await
        }
        async fn send_sigterm(&mut self) -> std::io::Result<()> {
            Ok(())
        }
        async fn send_sigkill(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn start_project_marks_healthy_when_child_responds() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/proj".into(), "proj".into(), Instant::now())
            .unwrap();

        let sup = Supervisor {
            registry: registry.clone(),
            spawner: ImmediateHealthySpawner,
            health_timeout: Duration::from_secs(2),
            children: Arc::new(Mutex::new(HashMap::new())),
        };
        sup.start_project("/tmp/proj".into()).await.unwrap();

        let r = registry.lock().await;
        let p = r.get(&PathBuf::from("/tmp/proj")).unwrap();
        assert!(matches!(p.state, ProjectState::Healthy { .. }));
    }

    /// Child that exits cleanly on SIGTERM after a configurable delay.
    struct DelayedExitChild {
        pid: u32,
        sigterm_to_exit: Duration,
        notify: Arc<tokio::sync::Notify>,
    }
    #[async_trait]
    impl ChildHandle for DelayedExitChild {
        fn pid(&self) -> u32 {
            self.pid
        }
        async fn wait(&mut self) -> std::io::Result<String> {
            self.notify.notified().await;
            Ok("exited".into())
        }
        async fn send_sigterm(&mut self) -> std::io::Result<()> {
            let n = self.notify.clone();
            let d = self.sigterm_to_exit;
            tokio::spawn(async move {
                tokio::time::sleep(d).await;
                n.notify_one();
            });
            Ok(())
        }
        async fn send_sigkill(&mut self) -> std::io::Result<()> {
            self.notify.notify_one();
            Ok(())
        }
    }

    #[tokio::test]
    async fn evict_terminates_quickly_on_sigterm() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let now = Instant::now();
        registry
            .lock()
            .await
            .insert_spawning("/tmp/p".into(), "p".into(), now)
            .unwrap();
        registry
            .lock()
            .await
            .transition_state(
                &PathBuf::from("/tmp/p"),
                ProjectState::Healthy {
                    port: 1,
                    pid: 999,
                    spawned_at: now,
                },
            )
            .unwrap();

        let child: Box<dyn ChildHandle> = Box::new(DelayedExitChild {
            pid: 999,
            sigterm_to_exit: Duration::from_millis(100),
            notify: Arc::new(tokio::sync::Notify::new()),
        });

        Supervisor::<ImmediateHealthySpawner>::evict(
            registry.clone(),
            "/tmp/p".into(),
            child,
            Duration::from_secs(2),
            Duration::from_secs(2),
        )
        .await;

        assert!(registry.lock().await.get(&PathBuf::from("/tmp/p")).is_none());
    }

    #[tokio::test]
    async fn trigger_eviction_kills_stored_child_and_drops_entry() {
        use std::sync::atomic::{AtomicBool, Ordering};
        let registry = Arc::new(Mutex::new(Registry::new()));
        let now = Instant::now();
        registry
            .lock()
            .await
            .insert_spawning("/tmp/p".into(), "p".into(), now)
            .unwrap();
        registry
            .lock()
            .await
            .transition_state(
                &PathBuf::from("/tmp/p"),
                ProjectState::Healthy {
                    port: 1,
                    pid: 7,
                    spawned_at: now,
                },
            )
            .unwrap();

        let was_killed = Arc::new(AtomicBool::new(false));
        let killed_clone = was_killed.clone();

        struct TrackingChild {
            killed: Arc<AtomicBool>,
            notify: Arc<tokio::sync::Notify>,
        }
        #[async_trait]
        impl ChildHandle for TrackingChild {
            fn pid(&self) -> u32 {
                7
            }
            async fn wait(&mut self) -> std::io::Result<String> {
                self.notify.notified().await;
                Ok("dead".into())
            }
            async fn send_sigterm(&mut self) -> std::io::Result<()> {
                self.killed.store(true, Ordering::SeqCst);
                self.notify.notify_one();
                Ok(())
            }
            async fn send_sigkill(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }

        let sup = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner: ImmediateHealthySpawner,
            health_timeout: Duration::from_secs(1),
            children: Arc::new(Mutex::new(std::collections::HashMap::new())),
        });
        let notify = Arc::new(tokio::sync::Notify::new());
        sup.insert_child(
            "/tmp/p".into(),
            Box::new(TrackingChild {
                killed: killed_clone,
                notify,
            }),
        )
        .await;

        sup.trigger_eviction(
            "/tmp/p".into(),
            Duration::from_secs(2),
            Duration::from_secs(2),
        );
        // Eviction is fire-and-forget; wait briefly for the spawned task to run.
        tokio::time::sleep(Duration::from_millis(200)).await;

        assert!(was_killed.load(Ordering::SeqCst));
        assert!(registry.lock().await.get(&PathBuf::from("/tmp/p")).is_none());
    }

    /// Mock spawner whose first 2 spawns exit immediately; the 3rd stays healthy.
    struct FlakySpawner {
        spawn_count: Arc<std::sync::atomic::AtomicUsize>,
    }
    #[async_trait]
    impl ChildSpawner for FlakySpawner {
        async fn spawn(&self, _dir: &Path, port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
            let n = self
                .spawn_count
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            if n < 2 {
                Ok(Box::new(MockChild { pid: 1 }))
            } else {
                let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
                tokio::spawn(async move {
                    use axum::routing::get;
                    let app = axum::Router::new().route("/", get(|| async { "ok" }));
                    axum::serve(listener, app).await.ok();
                });
                Ok(Box::new(MockChild { pid: 2 }))
            }
        }
    }

    #[tokio::test]
    async fn start_project_with_retries_eventually_succeeds() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/proj".into(), "proj".into(), Instant::now())
            .unwrap();
        let count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let sup = Supervisor {
            registry: registry.clone(),
            spawner: FlakySpawner {
                spawn_count: count.clone(),
            },
            health_timeout: Duration::from_millis(500),
            children: Arc::new(Mutex::new(HashMap::new())),
        };
        sup.start_project_with_retries("/tmp/proj".into(), 3, Duration::from_millis(50))
            .await
            .unwrap();

        assert_eq!(count.load(std::sync::atomic::Ordering::SeqCst), 3);
        let r = registry.lock().await;
        assert!(matches!(
            r.get(&PathBuf::from("/tmp/proj")).unwrap().state,
            ProjectState::Healthy { .. }
        ));
    }
}
