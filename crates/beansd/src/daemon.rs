use crate::health::{HealthChecker, HttpHealthChecker};
use crate::registry::{Project, ProjectState, Registry};
use crate::spawner::ChildSpawner;
use crate::supervisor::Supervisor;
use async_trait::async_trait;
use beansd_rpc::{
    CdResponse, Handler, LsResponse, ProjectState as RpcState, ProjectSummary, StartResponse,
    StatusResponse,
};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use std::time::Instant;
use tokio::sync::Mutex;

pub struct Daemon<S: ChildSpawner + 'static, H: HealthChecker = HttpHealthChecker> {
    pub registry: Arc<Mutex<Registry>>,
    pub supervisor: Arc<Supervisor<S, H>>,
    pub lru_cap: usize,
    pub sigterm_grace: Duration,
    pub sigkill_grace: Duration,
    pub start_max_attempts: usize,
    pub start_base_backoff: Duration,
}

#[async_trait]
impl<S: ChildSpawner + 'static, H: HealthChecker> Handler for Daemon<S, H> {
    async fn cd(&self, cwd: PathBuf) -> anyhow::Result<CdResponse> {
        let now = Instant::now();
        let key = match crate::project_key::resolve(&cwd)? {
            Some(k) => k,
            None => return Ok(CdResponse::NotRegistered),
        };

        let mut reg = self.registry.lock().await;
        if reg.get(&key).is_some() {
            reg.bump_last_used(&key, now);
            return Ok(CdResponse::Bumped { key });
        }

        // At cap → kick eviction of the LRU project. We may briefly hold
        // (cap + 1) entries until the eviction task removes the LRU one.
        if reg.count_active() >= self.lru_cap {
            if let Some(lru_key) = reg.find_lru_for_eviction() {
                self.supervisor
                    .trigger_eviction(lru_key, self.sigterm_grace, self.sigkill_grace);
            }
        }

        let display = key
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        let _ = reg.insert(Project::new(key.clone(), display, ProjectState::Spawning));
        drop(reg);

        let sup = self.supervisor.clone();
        let max = self.start_max_attempts;
        let backoff = self.start_base_backoff;
        let key_clone = key.clone();
        tokio::spawn(async move {
            if let Err(e) = sup
                .start_project_with_retries(key_clone, max, backoff)
                .await
            {
                tracing::error!(?e, "start_project failed");
            }
        });

        Ok(CdResponse::Spawned { key })
    }

    async fn ls(&self) -> anyhow::Result<LsResponse> {
        let reg = self.registry.lock().await;
        let projects = reg
            .iter()
            .map(|p| {
                let (state, port) = match &p.state {
                    ProjectState::Spawning { .. } => (RpcState::Spawning, None),
                    ProjectState::Healthy { port, .. } => (RpcState::Healthy, Some(*port)),
                    ProjectState::Evicting { .. } => (RpcState::Evicting, None),
                    ProjectState::Dead { .. } => (RpcState::Dead, None),
                };
                ProjectSummary {
                    key: p.key.clone(),
                    display_name: p.display_name.clone(),
                    state,
                    port,
                }
            })
            .collect();
        Ok(LsResponse { projects })
    }

    async fn start(&self, key: PathBuf) -> anyhow::Result<StartResponse> {
        let mut reg = self.registry.lock().await;
        match reg.get(&key).map(|p| &p.state) {
            Some(ProjectState::Healthy { .. } | ProjectState::Spawning { .. }) => {
                return Ok(StartResponse::AlreadyActive);
            }
            Some(_) => {
                let _ = reg.transition_state(&key, ProjectState::Spawning);
            }
            None => {
                anyhow::bail!("unknown project: {}", key.display());
            }
        }
        drop(reg);

        let sup = self.supervisor.clone();
        let max = self.start_max_attempts;
        let backoff = self.start_base_backoff;
        let key_clone = key.clone();
        tokio::spawn(async move {
            if let Err(e) = sup
                .start_project_with_retries(key_clone, max, backoff)
                .await
            {
                tracing::error!(?e, "start_project failed");
            }
        });
        Ok(StartResponse::Spawning)
    }

    async fn stop(&self, key: PathBuf) -> anyhow::Result<()> {
        let exists = self.registry.lock().await.get(&key).is_some();
        if !exists {
            anyhow::bail!("unknown project: {}", key.display());
        }
        self.supervisor
            .trigger_eviction(key, self.sigterm_grace, self.sigkill_grace);
        Ok(())
    }

    async fn status(&self) -> anyhow::Result<StatusResponse> {
        let reg = self.registry.lock().await;
        Ok(StatusResponse {
            registry_size: reg.iter().count(),
            active: reg.count_active(),
            lru_cap: self.lru_cap,
        })
    }

    async fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()> {
        self.registry
            .lock()
            .await
            .bump_last_used(&key, Instant::now());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::health::testing::MockHealthChecker;
    use crate::registry::{self, Registry};
    use crate::spawner::testing::MockChildHandle;
    use crate::spawner::ChildHandle;
    use crate::supervisor::Supervisor;
    use async_trait::async_trait;
    use std::path::Path;
    use std::sync::Arc;
    use std::time::Duration;
    use tempfile::tempdir;
    use tokio::sync::Mutex;

    pub(crate) struct NoOpSpawner;
    #[async_trait]
    impl ChildSpawner for NoOpSpawner {
        async fn spawn(
            &self,
            _dir: &std::path::Path,
            _port: u16,
        ) -> anyhow::Result<Box<dyn ChildHandle>> {
            Ok(Box::new(NoOpChild))
        }
    }

    pub(crate) struct NoOpChild;
    #[async_trait]
    impl ChildHandle for NoOpChild {
        fn pid(&self) -> u32 {
            1
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

    pub(crate) fn build_daemon(
        registry: Arc<Mutex<Registry>>,
    ) -> Daemon<NoOpSpawner, MockHealthChecker> {
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner: NoOpSpawner,
            health_checker: MockHealthChecker::always_ready(),
            health_attempts: 5,
            health_interval: Duration::from_millis(200),
        });
        Daemon {
            registry,
            supervisor,
            lru_cap: 8,
            sigterm_grace: Duration::from_secs(5),
            sigkill_grace: Duration::from_secs(5),
            start_max_attempts: 1,
            start_base_backoff: Duration::from_millis(10),
        }
    }

    #[tokio::test]
    async fn cd_no_marker_returns_not_registered() {
        let dir = tempdir().unwrap();
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry);
        let resp = d.cd(dir.path().to_path_buf()).await.unwrap();
        assert_eq!(resp, CdResponse::NotRegistered);
    }

    #[tokio::test]
    async fn cd_marked_dir_returns_spawned_then_eventually_healthy() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join(".beans.yml"), "").unwrap();
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry.clone());
        let resp = d.cd(dir.path().to_path_buf()).await.unwrap();
        let canonical = std::fs::canonicalize(dir.path()).unwrap();
        assert_eq!(
            resp,
            CdResponse::Spawned {
                key: canonical.clone()
            }
        );

        tokio::time::sleep(Duration::from_millis(500)).await;
        let r = registry.lock().await;
        assert!(matches!(
            r.get(&canonical).unwrap().state,
            ProjectState::Healthy { .. }
        ));
    }

    #[tokio::test]
    async fn cd_resolve_io_error_propagates() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry);
        let resp = d.cd(PathBuf::from("/no/such/path/at/all")).await;
        assert!(resp.is_err());
    }

    #[tokio::test]
    async fn ls_returns_empty_for_empty_registry() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry);
        let resp = d.ls().await.unwrap();
        assert_eq!(resp.projects.len(), 0);
    }

    #[tokio::test]
    async fn heartbeat_bumps_last_used() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/x".into(),
                "x".into(),
                ProjectState::Spawning,
            )],
        );
        let registry = Arc::new(Mutex::new(r));
        let d = build_daemon(registry.clone());
        let before = registry
            .lock()
            .await
            .get(Path::new("/tmp/x"))
            .unwrap()
            .last_used;
        tokio::time::sleep(Duration::from_millis(20)).await;
        d.heartbeat("/tmp/x".into()).await.unwrap();
        let after = registry
            .lock()
            .await
            .get(Path::new("/tmp/x"))
            .unwrap()
            .last_used;
        assert!(after > before);
    }

    #[tokio::test]
    async fn status_reports_size_and_cap() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/a".into(),
                "a".into(),
                ProjectState::Spawning,
            )],
        );
        let registry = Arc::new(Mutex::new(r));
        let d = build_daemon(registry);
        let r = d.status().await.unwrap();
        assert_eq!(r.registry_size, 1);
        assert_eq!(r.active, 1);
        assert_eq!(r.lru_cap, 8);
    }

    #[tokio::test]
    async fn stop_unknown_project_errors() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry);
        let r = d.stop("/tmp/missing".into()).await;
        assert!(r.is_err());
        assert!(r.err().unwrap().to_string().contains("unknown project"));
    }

    #[tokio::test]
    async fn start_unknown_project_errors() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry);
        let r = d.start("/tmp/missing".into()).await;
        assert!(r.is_err());
        assert!(r.err().unwrap().to_string().contains("unknown project"));
    }

    #[tokio::test]
    async fn start_already_healthy_returns_already_active() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/p".into(),
                "p".into(),
                ProjectState::Healthy {
                    port: 1,
                    child: Box::new(MockChildHandle),
                },
            )],
        );
        let registry = Arc::new(Mutex::new(r));
        let d = build_daemon(registry);
        let r = d.start("/tmp/p".into()).await.unwrap();
        assert_eq!(r, StartResponse::AlreadyActive);
    }
}
