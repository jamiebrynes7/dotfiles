use crate::registry::Registry;
use crate::spawner::ChildSpawner;
use crate::supervisor::Supervisor;
use anyhow::Context;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::Mutex;

pub fn default_socket_path() -> anyhow::Result<PathBuf> {
    if cfg!(target_os = "macos") {
        let home = std::env::var("HOME").context("HOME unset")?;
        Ok(PathBuf::from(home).join("Library/Caches/beans-daemon/sock"))
    } else {
        let xdg = std::env::var("XDG_RUNTIME_DIR").context("XDG_RUNTIME_DIR unset")?;
        Ok(PathBuf::from(xdg).join("beans-daemon.sock"))
    }
}

pub fn bind_uds(path: &Path) -> anyhow::Result<UnixListener> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    if path.exists() {
        if std::os::unix::net::UnixStream::connect(path).is_ok() {
            anyhow::bail!("socket {} already in use by a live daemon", path.display());
        }
        let _ = std::fs::remove_file(path);
    }
    let listener =
        UnixListener::bind(path).with_context(|| format!("binding {}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(listener)
}

pub struct Daemon<S: ChildSpawner + 'static> {
    pub registry: Arc<Mutex<Registry>>,
    pub supervisor: Arc<Supervisor<S>>,
    pub lru_cap: usize,
    pub sigterm_grace: Duration,
    pub sigkill_grace: Duration,
    pub start_max_attempts: usize,
    pub start_base_backoff: Duration,
}

impl<S: ChildSpawner + 'static> Daemon<S> {
    pub async fn handle_cd(&self, cwd: PathBuf) -> serde_json::Value {
        let now = Instant::now();
        let key = match crate::project_key::resolve(&cwd) {
            Ok(Some(k)) => k,
            Ok(None) => return serde_json::json!({ "registered": false }),
            Err(e) => {
                return serde_json::json!({ "registered": false, "error": e.to_string() });
            }
        };

        let mut reg = self.registry.lock().await;
        if reg.get(&key).is_some() {
            reg.bump_last_used(&key, now);
            return serde_json::json!({ "registered": true, "key": key, "action": "bumped" });
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
        let _ = reg.insert_spawning(key.clone(), display, now);
        drop(reg);

        let sup = self.supervisor.clone();
        let max = self.start_max_attempts;
        let backoff = self.start_base_backoff;
        let key_clone = key.clone();
        tokio::spawn(async move {
            if let Err(e) = sup.start_project_with_retries(key_clone, max, backoff).await {
                tracing::error!(?e, "start_project failed");
            }
        });

        serde_json::json!({ "registered": true, "key": key, "action": "spawned" })
    }

    pub async fn handle_ls(&self) -> serde_json::Value {
        let reg = self.registry.lock().await;
        let projects: Vec<_> = reg
            .iter()
            .map(|p| {
                let (state_label, port) = match &p.state {
                    crate::registry::ProjectState::Spawning { .. } => ("spawning", None),
                    crate::registry::ProjectState::Healthy { port, .. } => ("healthy", Some(*port)),
                    crate::registry::ProjectState::Evicting { .. } => ("evicting", None),
                    crate::registry::ProjectState::Dead { .. } => ("dead", None),
                };
                serde_json::json!({
                    "key": p.key,
                    "display_name": p.display_name,
                    "state": state_label,
                    "port": port,
                })
            })
            .collect();
        serde_json::json!({ "projects": projects })
    }

    pub async fn handle_status(&self) -> serde_json::Value {
        let reg = self.registry.lock().await;
        serde_json::json!({
            "registry_size": reg.iter().count(),
            "active":        reg.count_active(),
            "lru_cap":       self.lru_cap,
        })
    }

    pub async fn handle_heartbeat(&self, key: PathBuf) -> serde_json::Value {
        self.registry
            .lock()
            .await
            .bump_last_used(&key, Instant::now());
        serde_json::json!({ "bumped": true })
    }

    pub async fn handle_stop(&self, key: PathBuf) -> serde_json::Value {
        let exists = self.registry.lock().await.get(&key).is_some();
        if !exists {
            return serde_json::json!({ "stopped": false, "error": "unknown project" });
        }
        self.supervisor
            .trigger_eviction(key, self.sigterm_grace, self.sigkill_grace);
        serde_json::json!({ "stopped": true })
    }

    pub async fn handle_start(&self, key: PathBuf) -> serde_json::Value {
        use crate::registry::ProjectState;
        let now = Instant::now();
        let mut reg = self.registry.lock().await;
        match reg.get(&key).map(|p| &p.state) {
            Some(ProjectState::Healthy { .. } | ProjectState::Spawning { .. }) => {
                return serde_json::json!({ "started": true, "action": "already_active" });
            }
            Some(_) => {
                let _ = reg.transition_state(&key, ProjectState::Spawning { since: now });
            }
            None => {
                return serde_json::json!({ "started": false, "error": "unknown project" });
            }
        }
        drop(reg);

        let sup = self.supervisor.clone();
        let max = self.start_max_attempts;
        let backoff = self.start_base_backoff;
        let key_clone = key.clone();
        tokio::spawn(async move {
            if let Err(e) = sup.start_project_with_retries(key_clone, max, backoff).await {
                tracing::error!(?e, "start_project failed");
            }
        });
        serde_json::json!({ "started": true, "action": "spawning" })
    }

    pub async fn serve_uds(self: Arc<Self>, listener: UnixListener) -> anyhow::Result<()> {
        loop {
            let (sock, _addr) = listener.accept().await?;
            let me = self.clone();
            tokio::spawn(async move {
                if let Err(e) = me.handle_connection(sock).await {
                    tracing::warn!(error = ?e, "UDS connection ended with error");
                }
            });
        }
    }

    async fn handle_connection(&self, sock: UnixStream) -> anyhow::Result<()> {
        use crate::protocol::{Request, Response};
        let (rd, mut wr) = sock.into_split();
        let mut lines = BufReader::new(rd).lines();
        while let Some(line) = lines.next_line().await? {
            let req: Request = match serde_json::from_str(&line) {
                Ok(r) => r,
                Err(e) => {
                    let resp = Response::err(format!("bad request: {e}"));
                    let mut buf = serde_json::to_vec(&resp)?;
                    buf.push(b'\n');
                    let _ = wr.write_all(&buf).await;
                    continue;
                }
            };
            let data = match req {
                Request::Cd { cwd } => self.handle_cd(cwd).await,
                Request::Ls {} => self.handle_ls().await,
                Request::Start { key } => self.handle_start(key).await,
                Request::Stop { key } => self.handle_stop(key).await,
                Request::Status {} => self.handle_status().await,
                Request::Heartbeat { key } => self.handle_heartbeat(key).await,
            };
            let resp = Response::ok(data);
            let mut buf = serde_json::to_vec(&resp)?;
            buf.push(b'\n');
            // Best-effort: client may have closed the write half already
            // (fire-and-forget cd). Don't propagate broken-pipe errors.
            let _ = wr.write_all(&buf).await;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn bind_uds_creates_socket_with_0600() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("sock");
        let _l = bind_uds(&path).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[tokio::test]
    async fn bind_uds_unlinks_stale_socket() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("sock");
        std::fs::write(&path, b"").unwrap();
        let _l = bind_uds(&path).unwrap();
    }

    #[tokio::test]
    async fn bind_uds_refuses_to_replace_live_socket() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("sock");
        let _l1 = bind_uds(&path).unwrap();
        let res = bind_uds(&path);
        assert!(res.is_err());
        assert!(res.err().unwrap().to_string().contains("already in use"));
    }
}

#[cfg(test)]
mod cd_tests {
    use super::*;
    use crate::registry::ProjectState;
    use crate::spawner::ChildHandle;
    use async_trait::async_trait;
    use std::collections::HashMap;
    use tempfile::tempdir;

    pub(super) struct ImmediateHealthy;
    #[async_trait]
    impl ChildSpawner for ImmediateHealthy {
        async fn spawn(
            &self,
            _dir: &std::path::Path,
            port: u16,
        ) -> anyhow::Result<Box<dyn ChildHandle>> {
            let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
            tokio::spawn(async move {
                use axum::routing::get;
                let app = axum::Router::new().route("/", get(|| async { "ok" }));
                axum::serve(listener, app).await.ok();
            });
            Ok(Box::new(NoOpChild))
        }
    }

    pub(super) struct NoOpChild;
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

    pub(super) fn build_daemon(
        registry: Arc<Mutex<Registry>>,
        health_timeout: Duration,
    ) -> Daemon<ImmediateHealthy> {
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner: ImmediateHealthy,
            health_timeout,
            children: Arc::new(Mutex::new(HashMap::new())),
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
    async fn cd_into_dir_without_marker_reports_not_registered() {
        let dir = tempdir().unwrap();
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let resp = d.handle_cd(dir.path().to_path_buf()).await;
        assert_eq!(resp["registered"], false);
    }

    #[tokio::test]
    async fn cd_into_marked_dir_spawns_and_registers() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join(".beans.yml"), "").unwrap();
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry.clone(), Duration::from_secs(2));
        let resp = d.handle_cd(dir.path().to_path_buf()).await;
        assert_eq!(resp["registered"], true);
        assert_eq!(resp["action"], "spawned");

        tokio::time::sleep(Duration::from_millis(500)).await;
        let r = registry.lock().await;
        let canonical = std::fs::canonicalize(dir.path()).unwrap();
        assert!(matches!(
            r.get(&canonical).unwrap().state,
            ProjectState::Healthy { .. }
        ));
    }
}

#[cfg(test)]
mod handler_tests {
    use super::*;
    use super::cd_tests::build_daemon;

    #[tokio::test]
    async fn ls_returns_empty_projects_array() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.handle_ls().await;
        assert_eq!(r["projects"].as_array().unwrap().len(), 0);
    }

    #[tokio::test]
    async fn heartbeat_bumps_last_used() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/x".into(), "x".into(), Instant::now())
            .unwrap();
        let d = build_daemon(registry.clone(), Duration::from_secs(1));
        let before = registry.lock().await.get(Path::new("/tmp/x")).unwrap().last_used;
        tokio::time::sleep(Duration::from_millis(20)).await;
        d.handle_heartbeat("/tmp/x".into()).await;
        let after = registry.lock().await.get(Path::new("/tmp/x")).unwrap().last_used;
        assert!(after > before);
    }

    #[tokio::test]
    async fn status_reports_registry_size_and_cap() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/a".into(), "a".into(), Instant::now())
            .unwrap();
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.handle_status().await;
        assert_eq!(r["registry_size"], 1);
        assert_eq!(r["active"], 1);
        assert_eq!(r["lru_cap"], 8);
    }

    #[tokio::test]
    async fn stop_unknown_project_returns_error() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.handle_stop("/tmp/missing".into()).await;
        assert_eq!(r["stopped"], false);
    }

    #[tokio::test]
    async fn start_unknown_project_returns_error() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.handle_start("/tmp/missing".into()).await;
        assert_eq!(r["started"], false);
    }

    #[tokio::test]
    async fn round_trip_cd_via_uds() {
        use crate::protocol::Request;
        use tempfile::tempdir;

        let sock_dir = tempdir().unwrap();
        let sock_path = sock_dir.path().join("sock");
        let listener = bind_uds(&sock_path).unwrap();

        let registry = Arc::new(Mutex::new(Registry::new()));
        let daemon = Arc::new(build_daemon(registry, Duration::from_secs(1)));
        tokio::spawn(daemon.clone().serve_uds(listener));

        // No marker → handle_cd replies registered:false.
        let dir = tempdir().unwrap();
        let req = Request::Cd {
            cwd: dir.path().to_path_buf(),
        };
        let mut buf = serde_json::to_vec(&req).unwrap();
        buf.push(b'\n');

        let mut sock = UnixStream::connect(&sock_path).await.unwrap();
        sock.write_all(&buf).await.unwrap();
        sock.flush().await.unwrap();

        let mut lines = BufReader::new(sock).lines();
        let line = lines.next_line().await.unwrap().unwrap();
        assert!(line.contains(r#""ok":true"#));
        assert!(line.contains(r#""registered":false"#));
    }

    #[tokio::test]
    async fn malformed_request_returns_error_envelope() {
        use tempfile::tempdir;

        let sock_dir = tempdir().unwrap();
        let sock_path = sock_dir.path().join("sock");
        let listener = bind_uds(&sock_path).unwrap();

        let registry = Arc::new(Mutex::new(Registry::new()));
        let daemon = Arc::new(build_daemon(registry, Duration::from_secs(1)));
        tokio::spawn(daemon.clone().serve_uds(listener));

        let mut sock = UnixStream::connect(&sock_path).await.unwrap();
        sock.write_all(b"not json\n").await.unwrap();
        sock.flush().await.unwrap();

        let mut lines = BufReader::new(sock).lines();
        let line = lines.next_line().await.unwrap().unwrap();
        assert!(line.contains(r#""ok":false"#));
        assert!(line.contains("bad request"));
    }

    #[tokio::test]
    async fn start_already_healthy_is_noop() {
        use crate::registry::ProjectState;
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
                Path::new("/tmp/p"),
                ProjectState::Healthy {
                    port: 1,
                    pid: 2,
                    spawned_at: now,
                },
            )
            .unwrap();
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.handle_start("/tmp/p".into()).await;
        assert_eq!(r["started"], true);
        assert_eq!(r["action"], "already_active");
    }
}
