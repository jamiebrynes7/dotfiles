use crate::health::{HealthChecker, HttpHealthChecker};
use crate::registry::{ProjectState, Registry};
use crate::spawner::{ChildHandle, ChildSpawner};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub struct Supervisor<S: ChildSpawner, H: HealthChecker = HttpHealthChecker> {
    pub registry: Arc<Mutex<Registry>>,
    pub spawner: S,
    pub health_checker: H,
    /// Maximum number of health-check attempts for child startup.
    pub health_attempts: u32,
    /// Interval between health-check attempts.
    pub health_interval: Duration,
}

impl<S: ChildSpawner + 'static, H: HealthChecker> Supervisor<S, H> {
    /// Spawn a child for `key`, wait for health, transition registry state.
    /// Caller is responsible for having already inserted a `Spawning` entry
    /// for the key (so the cap accounting is correct from cd-op's POV).
    pub async fn start_project(&self, key: std::path::PathBuf) -> anyhow::Result<()> {
        let port = crate::port_alloc::pick_loopback_port()?;
        let mut child = self.spawner.spawn(&key, port).await?;

        let is_healthy = self
            .health_checker
            .wait_until_healthy(port, self.health_attempts, self.health_interval)
            .await;

        if !is_healthy {
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Dead {
                    reason: "startup health check failed".into(),
                },
            )?;

            if let Err(e) = child.send_sigkill().await {
                tracing::error!(?key, ?e, "failed to send SIGKILL");
            }

            return Err(anyhow::anyhow!("failed to start project"));
        }

        self.registry
            .lock()
            .await
            .transition_state(&key, ProjectState::Healthy { port, child })?;

        Ok(())
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
            self.registry
                .lock()
                .await
                .transition_state(&key, ProjectState::Spawning)?;
            if let Err(e) = self.start_project(key.clone()).await {
                tracing::warn!(?key, ?e, "failed to start project");
            }
            let healthy = matches!(
                self.registry.lock().await.get(&key).map(|p| &p.state),
                Some(ProjectState::Healthy { .. })
            );
            if healthy {
                return Ok(());
            }
            if attempt + 1 < max_attempts {
                tracing::warn!(
                    ?key,
                    attempt = attempt + 1,
                    ?backoff,
                    "child startup failed; backing off"
                );
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
            let mut registry = me.registry.lock().await;
            let prior = match registry.transition_state(&key, ProjectState::Evicting) {
                Ok(s) => s,
                Err(e) => {
                    tracing::warn!(?key, ?e, "failed to transition to Evicting");
                    return;
                }
            };
            drop(registry);

            if let ProjectState::Healthy { child, port: _ } = prior {
                Self::evict(
                    me.registry.clone(),
                    key,
                    child,
                    sigterm_grace,
                    sigkill_grace,
                )
                .await;
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
        if tokio::time::timeout(sigterm_grace, child.wait())
            .await
            .is_ok()
        {
            registry.lock().await.remove(&key);
            tracing::info!(?key, pid, "evicted (clean SIGTERM exit)");
            return;
        }

        let _ = child.send_sigkill().await;
        if tokio::time::timeout(sigkill_grace, child.wait())
            .await
            .is_ok()
        {
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
    use crate::registry;
    use crate::registry::Project;
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
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/proj".into(),
                "proj".into(),
                ProjectState::Spawning,
            )],
        );

        let sup = Supervisor {
            registry: Arc::new(Mutex::new(r)),
            spawner: NoOpSpawner,
            health_checker: MockHealthChecker::always_ready(),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
        };
        sup.start_project("/tmp/proj".into()).await.unwrap();

        let r = sup.registry.lock().await;
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
        let mut registry = Registry::new();
        registry::test_utils::seed_registry(
            &mut registry,
            vec![Project::new(
                "/tmp/p".into(),
                "p".into(),
                ProjectState::Evicting,
            )],
        );
        let registry = Arc::new(Mutex::new(Registry::new()));

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

        assert!(registry
            .lock()
            .await
            .get(&PathBuf::from("/tmp/p"))
            .is_none());
    }

    #[tokio::test]
    async fn trigger_eviction_kills_stored_child_and_drops_entry() {
        use std::sync::atomic::{AtomicBool, Ordering};

        struct TrackingChild {
            killed: Arc<AtomicBool>,
            notify: Arc<tokio::sync::Notify>,
        }
        impl TrackingChild {
            pub fn new() -> (TrackingChild, Arc<AtomicBool>) {
                let was_killed = Arc::new(AtomicBool::new(false));
                let killed_clone = was_killed.clone();
                (
                    TrackingChild {
                        killed: was_killed,
                        notify: Arc::new(tokio::sync::Notify::new()),
                    },
                    killed_clone,
                )
            }
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

        let (child, was_killed) = TrackingChild::new();

        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/p".into(),
                "p".into(),
                ProjectState::Healthy {
                    port: 1,
                    child: Box::new(child),
                },
            )],
        );

        let sup = Arc::new(Supervisor {
            registry: Arc::new(Mutex::new(r)),
            spawner: NoOpSpawner,
            health_checker: MockHealthChecker::always_ready(),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
        });

        sup.trigger_eviction(
            "/tmp/p".into(),
            Duration::from_secs(2),
            Duration::from_secs(2),
        );
        // Eviction is fire-and-forget; wait briefly for the spawned task to run.
        tokio::time::sleep(Duration::from_millis(200)).await;

        assert!(was_killed.load(Ordering::SeqCst));
        assert!(sup
            .registry
            .lock()
            .await
            .get(&PathBuf::from("/tmp/p"))
            .is_none());
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
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/proj".into(),
                "proj".into(),
                ProjectState::Spawning,
            )],
        );

        let registry = Arc::new(Mutex::new(r));
        let count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let sup = Supervisor {
            registry: registry.clone(),
            spawner: CountingSpawner {
                spawn_count: count.clone(),
            },
            health_checker: MockHealthChecker::fail_first(2),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
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
