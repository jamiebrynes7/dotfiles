use crate::registry::{ProjectState, Registry};
use crate::spawner::{ChildHandle, ChildSpawner};
use async_trait::async_trait;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

pub struct Supervisor<S: ChildSpawner> {
    pub registry: Arc<Mutex<Registry>>,
    pub spawner: S,
    /// Health-check timeout for child startup.
    pub health_timeout: Duration,
}

impl<S: ChildSpawner + 'static> Supervisor<S> {
    /// Spawn a child for `key`, wait for health, transition registry state.
    /// Caller is responsible for having already inserted a `Spawning` entry
    /// for the key (so the cap accounting is correct from cd-op's POV).
    pub async fn start_project(&self, key: std::path::PathBuf) -> anyhow::Result<()> {
        let port = crate::port_alloc::pick_loopback_port()?;
        let mut child = self.spawner.spawn(&key, port).await?;
        let pid = child.pid();
        let spawned_at = Instant::now();

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
            let _ = child.send_sigkill().await;
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
}
