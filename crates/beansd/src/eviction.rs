use std::{path::PathBuf, sync::Arc, time::Duration};

use tokio::{sync::Mutex, task::JoinHandle};

use crate::{
    registry::{ProjectState, Registry},
    supervisor::Supervisor,
};

pub struct EvictorConfig {
    pub lru_cap: usize,
    pub poll_interval: Duration,
}

pub struct Evictor {
    registry: Arc<Mutex<Registry>>,
    supervisor: Arc<dyn Supervisor>,
    config: EvictorConfig,
}

impl Evictor {
    pub fn new(
        registry: Arc<Mutex<Registry>>,
        supervisor: Arc<dyn Supervisor>,
        config: EvictorConfig,
    ) -> Self {
        Self {
            registry,
            supervisor,
            config,
        }
    }

    pub fn spawn(self) -> JoinHandle<anyhow::Result<()>> {
        tokio::spawn(async move {
            loop {
                tracing::trace!("running eviction check ...");
                self.run_one_sweep().await;
                tokio::time::sleep(self.config.poll_interval).await;
            }
        })
    }

    async fn run_one_sweep(&self) {
        while self.active_count().await > self.config.lru_cap {
            let Some(key) = self.find_lru().await else {
                break;
            };
            tracing::info!(?key, "evicting project");
            if let Err(e) = self.supervisor.stop(key).await {
                tracing::error!(?e, "failed to stop project");
            }
        }
    }

    async fn active_count(&self) -> usize {
        self.registry
            .lock()
            .await
            .iter()
            .filter(|p| matches!(p.state, ProjectState::Healthy { .. }))
            .count()
    }

    async fn find_lru(&self) -> Option<PathBuf> {
        self.registry
            .lock()
            .await
            .iter()
            .filter(|p| matches!(p.state, ProjectState::Healthy { .. }))
            .min_by_key(|p| p.last_used)
            .map(|p| p.key.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::{self, Project};
    use crate::spawner::testing::FakeChildHandle;
    use crate::supervisor::test_utils::FakeSupervisor;
    use std::path::Path;
    use std::time::Instant;

    fn healthy(key: &str) -> Project {
        Project::new(
            key.into(),
            key.into(),
            ProjectState::Healthy {
                port: 1,
                child: Box::new(FakeChildHandle::new(1)),
            },
        )
    }

    fn build_evictor(registry: Arc<Mutex<Registry>>, lru_cap: usize) -> Evictor {
        let supervisor = FakeSupervisor::new(registry.clone());
        Evictor::new(
            registry,
            supervisor,
            EvictorConfig {
                lru_cap,
                poll_interval: Duration::from_secs(60),
            },
        )
    }

    fn build_evictor_with_fake(
        registry: Arc<Mutex<Registry>>,
        lru_cap: usize,
    ) -> (Evictor, Arc<FakeSupervisor>) {
        let supervisor = FakeSupervisor::new(registry.clone());
        let evictor = Evictor::new(
            registry,
            supervisor.clone(),
            EvictorConfig {
                lru_cap,
                poll_interval: Duration::from_secs(60),
            },
        );
        (evictor, supervisor)
    }

    #[tokio::test]
    async fn lru_returns_none_when_empty() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let evictor = build_evictor(registry, 5);
        assert!(evictor.find_lru().await.is_none());
    }

    #[tokio::test]
    async fn lru_returns_none_when_no_healthy() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![
                Project::new("/tmp/a".into(), "a".into(), ProjectState::Spawning),
                Project::new("/tmp/b".into(), "b".into(), ProjectState::Evicting),
                Project::new(
                    "/tmp/c".into(),
                    "c".into(),
                    ProjectState::Dead { reason: "x".into() },
                ),
            ],
        );
        let evictor = build_evictor(Arc::new(Mutex::new(r)), 5);
        assert!(evictor.find_lru().await.is_none());
    }

    #[tokio::test]
    async fn lru_picks_oldest_healthy_by_last_used() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![healthy("/tmp/a"), healthy("/tmp/b"), healthy("/tmp/c")],
        );
        let t0 = Instant::now();
        r.bump_last_used(Path::new("/tmp/a"), t0);
        r.bump_last_used(Path::new("/tmp/b"), t0 + Duration::from_secs(1));
        r.bump_last_used(Path::new("/tmp/c"), t0 + Duration::from_secs(2));

        let evictor = build_evictor(Arc::new(Mutex::new(r)), 5);
        assert_eq!(evictor.find_lru().await, Some("/tmp/a".into()));
    }

    #[tokio::test]
    async fn lru_skips_non_healthy_states() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![
                Project::new("/tmp/a".into(), "a".into(), ProjectState::Evicting),
                healthy("/tmp/b"),
                Project::new("/tmp/c".into(), "c".into(), ProjectState::Spawning),
            ],
        );
        let t0 = Instant::now();
        // /tmp/a (Evicting) is "oldest" by last_used, but should be skipped.
        r.bump_last_used(Path::new("/tmp/a"), t0);
        r.bump_last_used(Path::new("/tmp/b"), t0 + Duration::from_secs(1));

        let evictor = build_evictor(Arc::new(Mutex::new(r)), 5);
        assert_eq!(evictor.find_lru().await, Some("/tmp/b".into()));
    }

    #[tokio::test]
    async fn sweep_noop_when_at_or_under_cap() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            (0..5)
                .map(|i| healthy(&format!("/tmp/{i}")))
                .collect(),
        );
        let (evictor, fake) = build_evictor_with_fake(Arc::new(Mutex::new(r)), 5);
        evictor.run_one_sweep().await;
        assert!(fake.stopped.lock().await.is_empty());
    }

    #[tokio::test]
    async fn sweep_evicts_one_when_one_over_cap() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            (0..6)
                .map(|i| healthy(&format!("/tmp/{i}")))
                .collect(),
        );
        let t0 = Instant::now();
        for i in 0..6 {
            r.bump_last_used(
                Path::new(&format!("/tmp/{i}")),
                t0 + Duration::from_secs(i as u64),
            );
        }

        let (evictor, fake) = build_evictor_with_fake(Arc::new(Mutex::new(r)), 5);
        evictor.run_one_sweep().await;

        let stopped = fake.stopped.lock().await.clone();
        assert_eq!(stopped, vec![PathBuf::from("/tmp/0")]);
    }

    #[tokio::test]
    async fn sweep_evicts_down_to_cap_in_lru_order() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            (0..8)
                .map(|i| healthy(&format!("/tmp/{i}")))
                .collect(),
        );
        let t0 = Instant::now();
        for i in 0..8 {
            r.bump_last_used(
                Path::new(&format!("/tmp/{i}")),
                t0 + Duration::from_secs(i as u64),
            );
        }

        let registry = Arc::new(Mutex::new(r));
        let (evictor, fake) = build_evictor_with_fake(registry.clone(), 5);
        evictor.run_one_sweep().await;

        let stopped = fake.stopped.lock().await.clone();
        assert_eq!(
            stopped,
            vec![
                PathBuf::from("/tmp/0"),
                PathBuf::from("/tmp/1"),
                PathBuf::from("/tmp/2"),
            ]
        );

        // And the surviving 5 are still Healthy.
        let r = registry.lock().await;
        for i in 3..8 {
            let p = r.get(Path::new(&format!("/tmp/{i}"))).unwrap();
            assert!(matches!(p.state, ProjectState::Healthy { .. }));
        }
    }
}
