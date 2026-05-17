use crate::health::{HealthChecker, HttpHealthChecker};
use crate::registry::{ProjectState, Registry};
use crate::spawner::{ChildHandle, ChildSpawner};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

pub struct Supervisor<S: ChildSpawner, H: HealthChecker = HttpHealthChecker> {
    pub registry: Arc<Mutex<Registry>>,
    pub spawner: S,
    pub health_checker: H,
    /// Maximum number of health-check attempts for child startup.
    pub health_attempts: u32,
    /// Interval between health-check attempts.
    pub health_interval: Duration,
    /// Live child handles, keyed by project path. Held so the supervisor
    /// can SIGTERM/SIGKILL them later (eviction, restart, shutdown).
    pub children: Arc<Mutex<HashMap<std::path::PathBuf, Box<dyn ChildHandle>>>>,
}

impl<S: ChildSpawner + 'static, H: HealthChecker> Supervisor<S, H> {
    /// Spawn a child for `key`, wait for health, transition registry state.
    /// Caller is responsible for having already inserted a `Spawning` entry
    /// for the key (so the cap accounting is correct from cd-op's POV).
    pub async fn start_project(&self, key: std::path::PathBuf) -> anyhow::Result<()> {
        let port = crate::port_alloc::pick_loopback_port()?;
        let child = self.spawner.spawn(&key, port).await?;
        let pid = child.pid();
        let spawned_at = Instant::now();
        self.children.lock().await.insert(key.clone(), child);

        if self
            .health_checker
            .wait_until_healthy(port, self.health_attempts, self.health_interval)
            .await
        {
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

    /// Spawn a task that awaits the stored child handle's `wait()`, then:
    ///   - marks the project Dead with the exit status as the reason,
    ///   - if `attempts_used + 1 < MAX_ATTEMPTS`, sleeps `backoff` and re-spawns
    ///     (single attempt via `start_project_with_retries`), then watches the
    ///     new child with incremented `attempts_used` and quadrupled backoff.
    /// Caller invokes this once after a successful health-check transition.
    pub fn watch_for_exit(
        self: &Arc<Self>,
        key: std::path::PathBuf,
        attempts_used: usize,
        backoff: Duration,
    ) {
        const MAX_ATTEMPTS: usize = 3;
        let me = self.clone();
        tokio::spawn(async move {
            let mut child = match me.children.lock().await.remove(&key) {
                Some(c) => c,
                None => return,
            };
            let exit = child
                .wait()
                .await
                .unwrap_or_else(|e| format!("wait error: {e}"));
            tracing::warn!(?key, exit, attempts_used, "child exited unexpectedly");

            me.registry
                .lock()
                .await
                .transition_state(
                    &key,
                    ProjectState::Dead {
                        reason: exit,
                        since: Instant::now(),
                    },
                )
                .ok();

            if attempts_used + 1 >= MAX_ATTEMPTS {
                return;
            }
            tokio::time::sleep(backoff).await;
            if me
                .start_project_with_retries(key.clone(), 1, Duration::from_millis(0))
                .await
                .is_ok()
            {
                me.watch_for_exit(key, attempts_used + 1, backoff * 4);
            }
        });
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
    use crate::health::testing::MockHealthChecker;
    use async_trait::async_trait;
    use std::path::Path;
    use std::path::PathBuf;

    /// Mock spawner: returns a no-op child without binding any port.
    /// Real-port health is exercised by the mock health checker, not the spawner.
    struct NoOpSpawner;
    #[async_trait]
    impl ChildSpawner for NoOpSpawner {
        async fn spawn(&self, _dir: &Path, _port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
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
            spawner: NoOpSpawner,
            health_checker: MockHealthChecker::always_ready(),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
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

        Supervisor::<NoOpSpawner, MockHealthChecker>::evict(
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
            spawner: NoOpSpawner,
            health_checker: MockHealthChecker::always_ready(),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
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

    /// Spawn counter for verifying retry behaviour. Always returns a no-op child;
    /// the mock health checker drives fail-twice-then-ready semantics.
    struct CountingSpawner {
        spawn_count: Arc<std::sync::atomic::AtomicUsize>,
    }
    #[async_trait]
    impl ChildSpawner for CountingSpawner {
        async fn spawn(&self, _dir: &Path, _port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
            self.spawn_count
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Ok(Box::new(MockChild { pid: 1 }))
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
            spawner: CountingSpawner {
                spawn_count: count.clone(),
            },
            health_checker: MockHealthChecker::fail_first(2),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
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

    /// Child that exits "unexpectedly" after a configurable delay.
    struct AutoExitChild {
        notify: Arc<tokio::sync::Notify>,
        exit_after: Duration,
    }
    #[async_trait]
    impl ChildHandle for AutoExitChild {
        fn pid(&self) -> u32 {
            100
        }
        async fn wait(&mut self) -> std::io::Result<String> {
            tokio::time::sleep(self.exit_after).await;
            self.notify.notify_one();
            Ok("crashed".into())
        }
        async fn send_sigterm(&mut self) -> std::io::Result<()> {
            Ok(())
        }
        async fn send_sigkill(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn watch_for_exit_marks_dead_when_child_crashes() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/p".into(), "p".into(), Instant::now())
            .unwrap();
        registry
            .lock()
            .await
            .transition_state(
                &PathBuf::from("/tmp/p"),
                ProjectState::Healthy {
                    port: 1,
                    pid: 100,
                    spawned_at: Instant::now(),
                },
            )
            .unwrap();

        let sup = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner: NoOpSpawner,
            health_checker: MockHealthChecker::always_ready(),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
            children: Arc::new(Mutex::new(HashMap::new())),
        });
        let notify = Arc::new(tokio::sync::Notify::new());
        let child: Box<dyn ChildHandle> = Box::new(AutoExitChild {
            notify: notify.clone(),
            exit_after: Duration::from_millis(100),
        });
        sup.insert_child("/tmp/p".into(), child).await;
        // attempts_used=2 means 2+1 == MAX_ATTEMPTS, so no retry — state stays Dead.
        sup.watch_for_exit("/tmp/p".into(), 2, Duration::from_millis(50));

        tokio::time::sleep(Duration::from_millis(500)).await;

        let r = registry.lock().await;
        assert!(matches!(
            r.get(&PathBuf::from("/tmp/p")).map(|p| &p.state),
            Some(ProjectState::Dead { .. })
        ));
    }
}
