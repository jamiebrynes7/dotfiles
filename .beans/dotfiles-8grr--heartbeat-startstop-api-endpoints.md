---
# dotfiles-8grr
title: Heartbeat + start/stop API endpoints
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:39:41Z
updated_at: 2026-05-10T14:01:40Z
parent: dotfiles-60yo
---

**Files:**
- Modify: `packages/beans-daemon/src/launcher.rs`

These endpoints accept form-encoded `key=<abs-path>` (HTMX's default `hx-vals` JSON also works as form data when `application/x-www-form-urlencoded` is the content-type, which axum's `Form` extractor handles).

The launcher needs access to the same `Daemon` struct from F5 to dispatch these — the LauncherState gets a `Daemon` field too.

- [x] **Step 1: Extend LauncherState with the Daemon handle**

Modify `packages/beans-daemon/src/launcher.rs`:
```rust
use crate::control::Daemon;
use crate::spawner::ChildSpawner;

#[derive(Clone)]
pub struct LauncherState<S: ChildSpawner + 'static> {
    pub registry: Arc<Mutex<Registry>>,
    pub daemon:   Arc<Daemon<S>>,
}
```

(All previous handlers and `router_with_state` need to be parameterised over `S`. This is a refactor — the test fixtures in `mod tests` will pick a concrete `S`.)

- [x] **Step 2: Add the API handlers**

Append to `packages/beans-daemon/src/launcher.rs`:
```rust
#[derive(serde::Deserialize)]
struct KeyForm { key: PathBuf }

async fn heartbeat<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    state.daemon.handle_heartbeat(f.key).await;
    axum::http::StatusCode::NO_CONTENT
}

async fn stop_project<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    state.daemon.handle_stop(f.key).await;
    // Return the updated full list partial so HTMX can swap it.
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial { projects: project_views(&reg), active_key: None };
    axum::response::Html(tmpl.render().unwrap())
}

async fn start_project<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    state.daemon.handle_start(f.key).await;
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial { projects: project_views(&reg), active_key: None };
    axum::response::Html(tmpl.render().unwrap())
}
```

Add to `router_with_state`:
```rust
        .route("/api/heartbeat",        axum::routing::post(heartbeat::<S>))
        .route("/api/projects/start",   axum::routing::post(start_project::<S>))
        .route("/api/projects/stop",    axum::routing::post(stop_project::<S>))
```

- [x] **Step 3: Test it**

Append to `mod tests`:
```rust
    use crate::supervisor::Supervisor;
    use std::time::Duration;

    fn test_state() -> LauncherState<crate::launcher::tests::MockSpawner> {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner:  MockSpawner,
            health_timeout: Duration::from_secs(1),
        });
        let daemon = Arc::new(Daemon {
            registry: registry.clone(), supervisor, lru_cap: 8,
            sigterm_grace: Duration::from_secs(5),
            sigkill_grace: Duration::from_secs(5),
            start_max_attempts: 1,
            start_base_backoff: Duration::from_millis(10),
        });
        LauncherState { registry, daemon }
    }

    pub struct MockSpawner;
    #[async_trait::async_trait]
    impl ChildSpawner for MockSpawner {
        async fn spawn(&self, _dir: &std::path::Path, port: u16) -> anyhow::Result<Box<dyn crate::spawner::ChildHandle>> {
            // Just return a no-op child; tests for heartbeat/stop/start don't need a real listener.
            struct C;
            #[async_trait::async_trait]
            impl crate::spawner::ChildHandle for C {
                fn pid(&self) -> u32 { 0 }
                async fn wait(&mut self) -> std::io::Result<String> { std::future::pending().await }
                async fn send_sigterm(&mut self) -> std::io::Result<()> { Ok(()) }
                async fn send_sigkill(&mut self) -> std::io::Result<()> { Ok(()) }
            }
            Ok(Box::new(C))
        }
    }

    #[tokio::test]
    async fn heartbeat_returns_204() {
        let state = test_state();
        state.registry.lock().await.insert_spawning("/tmp/x".into(), "x".into(), Instant::now()).unwrap();
        let app = router_with_state(state);
        let resp = app.oneshot(
            Request::post("/api/heartbeat")
                .header("content-type", "application/x-www-form-urlencoded")
                .body(axum::body::Body::from("key=/tmp/x")).unwrap()
        ).await.unwrap();
        assert_eq!(resp.status(), StatusCode::NO_CONTENT);
    }
```

- [x] **Step 4: Run tests**

Run: `cargo test launcher::`
Expected: all tests pass.

- [x] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/launcher.rs
git commit -m "packages/beans-daemon: heartbeat + start/stop API endpoints"
```

## Summary of Changes

Refactored `LauncherState` to be generic over `S: ChildSpawner + 'static` and added an `Arc<Daemon<S>>` field. Manual `Clone` impl avoids requiring `S: Clone`. Made `index`, `projects_partial`, `heartbeat`, `start_project`, `stop_project`, and `router_with_state` generic over `S` accordingly. Added three POST endpoints: `/api/heartbeat` (204), `/api/projects/start` and `/api/projects/stop` (both return the refreshed project-list partial as HTMX swap target). Tests use a `MockSpawner` no-op fixture; new tests cover `heartbeat` 204 + `last_used` bump, and `stop` returning HTML 200.
