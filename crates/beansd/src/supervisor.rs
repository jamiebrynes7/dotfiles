use crate::health::{HealthChecker, HttpHealthChecker};
use crate::registry::{ProjectState, Registry};
use crate::spawner::ChildSpawner;
use axum::async_trait;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

#[async_trait]
pub trait Supervisor: Send + Sync + 'static {
    async fn start(&self, key: std::path::PathBuf) -> anyhow::Result<()>;
    async fn stop(&self, key: std::path::PathBuf) -> anyhow::Result<()>;
}

pub fn new<S: ChildSpawner + 'static, H: HealthChecker>(
    registry: Arc<Mutex<Registry>>,
    spawner: S,
    health_checker: H,
) -> Arc<dyn Supervisor> {
    let s = SupervisorImpl {
        registry,
        spawner,
        health_checker,
        health_attempts: 5,
        health_interval: Duration::from_secs(1),
    };
    Arc::new(s)
}

struct SupervisorImpl<S: ChildSpawner, H: HealthChecker = HttpHealthChecker> {
    pub registry: Arc<Mutex<Registry>>,
    pub spawner: S,
    pub health_checker: H,
    /// Maximum number of health-check attempts for child startup.
    pub health_attempts: u32,
    /// Interval between health-check attempts.
    pub health_interval: Duration,
}

#[async_trait]
impl<S: ChildSpawner + 'static, H: HealthChecker> Supervisor for SupervisorImpl<S, H> {
    async fn start(&self, key: std::path::PathBuf) -> anyhow::Result<()> {
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

            if let Err(e) = child.kill().await {
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

    async fn stop(&self, key: std::path::PathBuf) -> anyhow::Result<()> {
        tracing::info!(?key, "stopping project");
        // TODO: Add cmp and swap state function.
        let is_active = match self.registry.lock().await.get(&key) {
            Some(p) => matches!(p.state, ProjectState::Healthy { .. }),
            None => return Ok(()),
        };

        if !is_active {
            return Ok(());
        }

        let prior = self
            .registry
            .lock()
            .await
            .transition_state(&key, ProjectState::Evicting)?;

        if let ProjectState::Healthy { mut child, .. } = prior {
            child.kill().await?;

            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Dead {
                    reason: "Process evicted".into(),
                },
            )?;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::health::testing::MockHealthChecker;
    use crate::registry::{self, Project};
    use crate::spawner::testing::{FakeChildHandle, FakeSpawner};
    use crate::spawner::ChildHandle;
    use std::path::PathBuf;

    fn seeded(state: ProjectState) -> Arc<Mutex<Registry>> {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new("/tmp/proj".into(), "proj".into(), state)],
        );
        Arc::new(Mutex::new(r))
    }

    fn build_supervisor<S: ChildSpawner + 'static, H: HealthChecker>(
        registry: Arc<Mutex<Registry>>,
        spawner: S,
        health: H,
        health_attempts: u32,
    ) -> SupervisorImpl<S, H> {
        SupervisorImpl {
            registry,
            spawner,
            health_checker: health,
            health_attempts,
            health_interval: Duration::from_millis(10),
        }
    }

    #[tokio::test]
    async fn start_marks_healthy_when_child_responds() {
        let registry = seeded(ProjectState::Spawning);
        let sup = build_supervisor(
            registry.clone(),
            FakeSpawner::new(),
            MockHealthChecker::always_ready(),
            5,
        );

        sup.start("/tmp/proj".into()).await.unwrap();

        let r = registry.lock().await;
        let p = r.get(&PathBuf::from("/tmp/proj")).unwrap();
        assert!(matches!(p.state, ProjectState::Healthy { .. }));
    }

    #[tokio::test]
    async fn start_marks_dead_when_health_fails() {
        let registry = seeded(ProjectState::Spawning);
        let sup = build_supervisor(
            registry.clone(),
            FakeSpawner::new(),
            MockHealthChecker::never_ready(),
            1,
        );

        let err = sup.start("/tmp/proj".into()).await.unwrap_err();
        assert!(err.to_string().contains("failed to start project"));

        let r = registry.lock().await;
        let p = r.get(&PathBuf::from("/tmp/proj")).unwrap();
        assert!(matches!(p.state, ProjectState::Dead { .. }));
        drop(r);

        // The child the spawner produced should have been killed.
        let children = sup.spawner.children().await;
        assert_eq!(children.len(), 1);
        let mut probe = children[0].clone();
        tokio::time::timeout(Duration::from_millis(100), probe.wait())
            .await
            .expect("kill() should have unblocked wait()")
            .unwrap();
    }

    #[tokio::test]
    async fn stop_transitions_healthy_to_dead_and_kills_child() {
        let child = FakeChildHandle::new(7);
        let probe = child.clone();

        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/p".into(),
                "p".into(),
                ProjectState::Healthy {
                    port: 1234,
                    child: Box::new(child),
                },
            )],
        );
        let registry = Arc::new(Mutex::new(r));

        let sup = build_supervisor(
            registry.clone(),
            FakeSpawner::new(),
            MockHealthChecker::always_ready(),
            5,
        );

        sup.stop("/tmp/p".into()).await.unwrap();

        let r = registry.lock().await;
        let p = r.get(&PathBuf::from("/tmp/p")).unwrap();
        assert!(matches!(p.state, ProjectState::Dead { .. }));

        let mut probe = probe;
        tokio::time::timeout(Duration::from_millis(100), probe.wait())
            .await
            .expect("kill() should have unblocked wait()")
            .unwrap();
    }

    #[tokio::test]
    async fn stop_on_unknown_key_is_noop() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let sup = build_supervisor(
            registry.clone(),
            FakeSpawner::new(),
            MockHealthChecker::always_ready(),
            5,
        );
        sup.stop("/tmp/missing".into()).await.unwrap();
    }

    #[tokio::test]
    async fn stop_on_non_healthy_is_noop() {
        let registry = seeded(ProjectState::Spawning);
        let sup = build_supervisor(
            registry.clone(),
            FakeSpawner::new(),
            MockHealthChecker::always_ready(),
            5,
        );
        sup.stop("/tmp/proj".into()).await.unwrap();

        let r = registry.lock().await;
        let p = r.get(&PathBuf::from("/tmp/proj")).unwrap();
        assert!(matches!(p.state, ProjectState::Spawning));
    }
}

#[cfg(test)]
pub mod test_utils {
    use std::{path::PathBuf, sync::Arc};

    use axum::async_trait;
    use tokio::sync::Mutex;

    use crate::registry::{ProjectState, Registry};
    use crate::spawner::testing::FakeChildHandle;
    use crate::supervisor::Supervisor;

    pub struct FakeSupervisor {
        registry: Arc<Mutex<Registry>>,
        pub started: Arc<Mutex<Vec<PathBuf>>>,
        pub stopped: Arc<Mutex<Vec<PathBuf>>>,
    }

    impl FakeSupervisor {
        pub fn new(registry: Arc<Mutex<Registry>>) -> Arc<Self> {
            Arc::new(Self {
                registry,
                started: Arc::new(Mutex::new(Vec::new())),
                stopped: Arc::new(Mutex::new(Vec::new())),
            })
        }
    }

    #[async_trait]
    impl Supervisor for FakeSupervisor {
        async fn start(&self, key: PathBuf) -> anyhow::Result<()> {
            self.started.lock().await.push(key.clone());
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Healthy {
                    port: 1,
                    child: Box::new(FakeChildHandle::new(1)),
                },
            )?;
            Ok(())
        }

        async fn stop(&self, key: PathBuf) -> anyhow::Result<()> {
            self.stopped.lock().await.push(key.clone());
            let mut reg = self.registry.lock().await;
            if let Some(p) = reg.get(&key) {
                if matches!(p.state, ProjectState::Healthy { .. }) {
                    let _ = reg.transition_state(
                        &key,
                        ProjectState::Dead {
                            reason: "fake stop".into(),
                        },
                    );
                }
            }
            Ok(())
        }
    }
}
