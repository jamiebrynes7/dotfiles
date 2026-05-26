---
# dotfiles-erte
title: Daemon implements Handler typed; run.rs uses serve
status: completed
type: task
priority: normal
created_at: 2026-05-10T14:58:04Z
updated_at: 2026-05-16T07:39:30Z
parent: dotfiles-qwfb
blocked_by:
    - dotfiles-75b5
---

**Files:**
- Create: `crates/beansd/src/daemon.rs` (Daemon struct moves here from control.rs)
- Create: `crates/beansd/src/handler.rs` (typed `Handler` impl on `Daemon<S>`)
- Delete: `crates/beansd/src/control.rs` (contents redistributed)
- Modify: `crates/beansd/src/main.rs` (drop `mod control`; add `mod daemon; mod handler;`)
- Modify: `crates/beansd/src/run.rs` (call `beansd_rpc::serve`)
- Modify: `crates/beansd/src/launcher.rs` (call sites use trait methods + handle `Result`)

The biggest task. Single coherent commit: daemon stops owning the dispatch/wire-format glue. Tests rewritten to assert typed shape.

- [x] **Step 1: Create `crates/beansd/src/daemon.rs`**

Move the `Daemon` struct and its non-handler methods (none today — only fields) here. New file:

```rust
use crate::registry::Registry;
use crate::spawner::ChildSpawner;
use crate::supervisor::Supervisor;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub struct Daemon<S: ChildSpawner + 'static> {
    pub registry: Arc<Mutex<Registry>>,
    pub supervisor: Arc<Supervisor<S>>,
    pub lru_cap: usize,
    pub sigterm_grace: Duration,
    pub sigkill_grace: Duration,
    pub start_max_attempts: usize,
    pub start_base_backoff: Duration,
}
```

- [x] **Step 2: Create `crates/beansd/src/handler.rs`**

Implement the `beansd_rpc::Handler` trait on `Daemon<S>`. Bodies are the existing `Daemon::handle_*` logic, with typed return values and bad-input failures bubbled as `Err`:

```rust
use crate::daemon::Daemon;
use crate::registry::ProjectState;
use crate::spawner::ChildSpawner;
use async_trait::async_trait;
use beansd_rpc::{
    CdResponse, Handler, LsResponse, ProjectState as RpcState, ProjectSummary, StartResponse,
    StatusResponse,
};
use std::path::PathBuf;
use std::time::Instant;

#[async_trait]
impl<S: ChildSpawner + 'static> Handler for Daemon<S> {
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
        let now = Instant::now();
        let mut reg = self.registry.lock().await;
        match reg.get(&key).map(|p| &p.state) {
            Some(ProjectState::Healthy { .. } | ProjectState::Spawning { .. }) => {
                return Ok(StartResponse::AlreadyActive);
            }
            Some(_) => {
                let _ = reg.transition_state(&key, ProjectState::Spawning { since: now });
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
            if let Err(e) = sup.start_project_with_retries(key_clone, max, backoff).await {
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
    use crate::registry::Registry;
    use crate::spawner::ChildHandle;
    use crate::supervisor::Supervisor;
    use async_trait::async_trait;
    use std::collections::HashMap;
    use std::path::Path;
    use std::sync::Arc;
    use std::time::Duration;
    use tempfile::tempdir;
    use tokio::sync::Mutex;

    pub(crate) struct ImmediateHealthy;
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

    pub(crate) struct NoOpChild;
    #[async_trait]
    impl ChildHandle for NoOpChild {
        fn pid(&self) -> u32 { 1 }
        async fn wait(&mut self) -> std::io::Result<String> { std::future::pending().await }
        async fn send_sigterm(&mut self) -> std::io::Result<()> { Ok(()) }
        async fn send_sigkill(&mut self) -> std::io::Result<()> { Ok(()) }
    }

    pub(crate) fn build_daemon(
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
    async fn cd_no_marker_returns_not_registered() {
        let dir = tempdir().unwrap();
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let resp = d.cd(dir.path().to_path_buf()).await.unwrap();
        assert_eq!(resp, CdResponse::NotRegistered);
    }

    #[tokio::test]
    async fn cd_marked_dir_returns_spawned_then_eventually_healthy() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join(".beans.yml"), "").unwrap();
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry.clone(), Duration::from_secs(2));
        let resp = d.cd(dir.path().to_path_buf()).await.unwrap();
        let canonical = std::fs::canonicalize(dir.path()).unwrap();
        assert_eq!(resp, CdResponse::Spawned { key: canonical.clone() });

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
        let d = build_daemon(registry, Duration::from_secs(1));
        let resp = d.cd(PathBuf::from("/no/such/path/at/all")).await;
        assert!(resp.is_err());
    }

    #[tokio::test]
    async fn ls_returns_empty_for_empty_registry() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let resp = d.ls().await.unwrap();
        assert_eq!(resp.projects.len(), 0);
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
        d.heartbeat("/tmp/x".into()).await.unwrap();
        let after = registry.lock().await.get(Path::new("/tmp/x")).unwrap().last_used;
        assert!(after > before);
    }

    #[tokio::test]
    async fn status_reports_size_and_cap() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/a".into(), "a".into(), Instant::now())
            .unwrap();
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.status().await.unwrap();
        assert_eq!(r.registry_size, 1);
        assert_eq!(r.active, 1);
        assert_eq!(r.lru_cap, 8);
    }

    #[tokio::test]
    async fn stop_unknown_project_errors() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.stop("/tmp/missing".into()).await;
        assert!(r.is_err());
        assert!(r.err().unwrap().to_string().contains("unknown project"));
    }

    #[tokio::test]
    async fn start_unknown_project_errors() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.start("/tmp/missing".into()).await;
        assert!(r.is_err());
        assert!(r.err().unwrap().to_string().contains("unknown project"));
    }

    #[tokio::test]
    async fn start_already_healthy_returns_already_active() {
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
                ProjectState::Healthy { port: 1, pid: 2, spawned_at: now },
            )
            .unwrap();
        let d = build_daemon(registry, Duration::from_secs(1));
        let r = d.start("/tmp/p".into()).await.unwrap();
        assert_eq!(r, StartResponse::AlreadyActive);
    }
}
```

- [x] **Step 3: Delete `crates/beansd/src/control.rs`**

```bash
git rm crates/beansd/src/control.rs
```

The `Daemon` struct now lives in `daemon.rs`; the `handle_*` / `serve_uds` / `handle_connection` methods are replaced by the `Handler` impl in `handler.rs` and `beansd_rpc::serve`. The bind/socket helpers are in `beansd-rpc::socket`. Nothing left to keep.

- [x] **Step 4: Update `crates/beansd/src/main.rs`**

Replace the `mod` block:

```rust
mod cli;
mod cli_client;
mod config;
mod daemon;
mod handler;
mod launcher;
mod logging;
mod port_alloc;
mod project_key;
mod registry;
mod run;
mod spawner;
mod supervisor;
```

(`mod control;` removed; `mod daemon;` and `mod handler;` added.)

- [x] **Step 5: Update `crates/beansd/src/run.rs`**

Replace:

```rust
use crate::control::Daemon;
```

with:

```rust
use crate::daemon::Daemon;
```

Replace the UDS-server-spawn block:

```rust
    let uds_task = {
        let d = daemon.clone();
        tokio::spawn(async move { d.serve_uds(uds_listener).await })
    };
```

with:

```rust
    let uds_task = {
        let d = daemon.clone();
        tokio::spawn(async move { beansd_rpc::serve(uds_listener, d).await })
    };
```

Rest of `run.rs` unchanged.

- [x] **Step 6: Update `crates/beansd/src/launcher.rs`**

The launcher's `LauncherState<S: ChildSpawner>` carries `Arc<Daemon<S>>`. Replace `use crate::control::Daemon;` with `use crate::daemon::Daemon;`.

The three handlers that go through the daemon need to invoke trait methods (now `daemon.heartbeat(...)`, `daemon.start(...)`, `daemon.stop(...)`) and handle `Result`:

```rust
async fn heartbeat<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    use beansd_rpc::Handler;
    match state.daemon.heartbeat(f.key).await {
        Ok(()) => axum::http::StatusCode::NO_CONTENT,
        Err(_) => axum::http::StatusCode::INTERNAL_SERVER_ERROR,
    }
}

async fn stop_project<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> axum::response::Response {
    use beansd_rpc::Handler;
    if let Err(_) = state.daemon.stop(f.key).await {
        return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial { projects: project_views(&reg), active_key: None };
    axum::response::Html(tmpl.render().unwrap()).into_response()
}

async fn start_project<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> axum::response::Response {
    use beansd_rpc::Handler;
    if let Err(_) = state.daemon.start(f.key).await {
        return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial { projects: project_views(&reg), active_key: None };
    axum::response::Html(tmpl.render().unwrap()).into_response()
}
```

Note: the start/stop handlers' return type changes from `impl IntoResponse` to `axum::response::Response` so the `Err` path can return a different status code. Add `use axum::response::IntoResponse;` if not present (already imported in this file).

The `ProjectView` mapping stays unchanged — the launcher's local `ProjectView` and `LsResponse::projects` from beansd-rpc are independent (the launcher renders templates with the local one).

The launcher's existing tests (`heartbeat_returns_204_and_bumps_last_used`, `stop_returns_partial_html`) still pass — `MockSpawner` from the test module makes the handler trait calls succeed.

- [x] **Step 7: Run beansd tests**

```bash
nix develop --command cargo test --manifest-path Cargo.toml -p beansd
```

Expected: 9 handler tests (replacing today's 10 cd/handler tests with one consolidation) + 8 launcher tests + remaining infrastructure tests = ~50 tests pass for the daemon crate. Plus today's `mod tests` blocks for registry, supervisor, config, etc., remain green.

- [x] **Step 8: Run the full workspace test suite**

```bash
nix develop --command cargo test --manifest-path Cargo.toml --workspace
```

Expected: full suite green. Net: 17 in beansd-rpc + 53 in beansd = 70 total (today's 10 cd/handler tests are replaced by 9 typed tests in handler.rs — net −1 in beansd; serve dispatch tests are already covered in beansd-rpc::server).

- [x] **Step 9: Commit**

```bash
git add Cargo.lock crates/
git commit -m "crates/beansd: implement Handler typed; serve via beansd-rpc"
```

## Summary of Changes

- New `crates/beansd/src/daemon.rs` — `Daemon<S>` struct moved here (fields only; previously in control.rs).
- New `crates/beansd/src/handler.rs` — `beansd_rpc::Handler` impl on `Daemon<S>` with typed returns. Bad-input cases (`stop`/`start` for unknown project, `cd` for missing path) now bubble as `anyhow::Err` rather than embedding error strings in JSON payloads. Includes 9 typed tests covering all ops.
- Deleted `crates/beansd/src/control.rs` — dispatch/wire-format glue is now in `beansd-rpc::server`; socket bind helpers in `beansd-rpc::socket`.
- `crates/beansd/src/main.rs` — dropped `mod control`, added `mod daemon; mod handler;`.
- `crates/beansd/src/run.rs` — `tokio::spawn(d.serve_uds(...))` replaced with `tokio::spawn(beansd_rpc::serve(uds_listener, d))`.
- `crates/beansd/src/launcher.rs` — the three handler-using axum routes (`heartbeat`, `stop_project`, `start_project`) now go through trait methods on `beansd_rpc::Handler` and translate `Err` → 500. `stop_project`/`start_project` return types changed from `impl IntoResponse` to `axum::response::Response` to accommodate the new error branch.
- `cargo test --workspace` → 70 passing (53 beansd + 17 beansd-rpc); matches the spec target.
