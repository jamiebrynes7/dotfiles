---
# dotfiles-bqzh
title: Migrate start/stop handlers into api/projects.rs
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:07:59Z
updated_at: 2026-05-24T15:09:16Z
parent: dotfiles-p6a4
blocked_by:
    - dotfiles-7iu6
---

**Files:**
- Replace: `crates/beansd/src/web/routes/api/projects.rs` (was a stub from dotfiles-ms85)
- Source: copy from `crates/beansd/src/launcher.rs:121-151` (handlers) and `358-382` (test)

- [ ] **Step 1: Replace `crates/beansd/src/web/routes/api/projects.rs`**

```rust
use crate::web::routes::api::KeyForm;
use crate::web::routes::html::projects::ProjectListPartial;
use crate::web::views::project_views;
use crate::web::State;
use askama::Template;
use axum::response::IntoResponse;
use axum::{routing::post, Router};

async fn start_project(
    axum::extract::State(state): axum::extract::State<State>,
    axum::Form(f): axum::Form<KeyForm>,
) -> axum::response::Response {
    use beansd_rpc::Handler;
    if state.daemon.start(f.key).await.is_err() {
        return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: None,
    };
    axum::response::Html(tmpl.render().unwrap()).into_response()
}

async fn stop_project(
    axum::extract::State(state): axum::extract::State<State>,
    axum::Form(f): axum::Form<KeyForm>,
) -> axum::response::Response {
    use beansd_rpc::Handler;
    if state.daemon.stop(f.key).await.is_err() {
        return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: None,
    };
    axum::response::Html(tmpl.render().unwrap()).into_response()
}

pub(super) fn router() -> Router<State> {
    Router::new()
        .route("/api/projects/start", post(start_project))
        .route("/api/projects/stop", post(stop_project))
}

#[cfg(test)]
mod tests {
    use crate::registry::{self, Project, ProjectState, Registry};
    use crate::web::test_utils::{build_state, router_with_state};
    use axum::http::{Request, StatusCode};
    use std::sync::Arc;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    #[tokio::test]
    async fn stop_returns_partial_html() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/y".into(),
                "y".into(),
                ProjectState::Spawning,
            )],
        );
        let registry = Arc::new(Mutex::new(r));

        let app = router_with_state(build_state(registry));
        let resp = app
            .oneshot(
                Request::post("/api/projects/stop")
                    .header("content-type", "application/x-www-form-urlencoded")
                    .body(axum::body::Body::from("key=/tmp/y"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }
}
```

Dependencies:
- `crate::web::routes::api::KeyForm` from `api/mod.rs` (created in dotfiles-ms85).
- `crate::web::routes::html::projects::ProjectListPartial` from html/projects.rs (created in dotfiles-tlhu) — that's why this task is blocked by dotfiles-tlhu.
- `crate::web::test_utils::{build_state, router_with_state}` (added to `web/mod.rs` in dotfiles-tlhu).

- [ ] **Step 2: Build and run tests**

```bash
cargo test -p beansd
```

Expected: 13 tests pass — 8 launcher + 4 html + 1 new `web::routes::api::projects::tests::stop_returns_partial_html`.

- [ ] **Step 3: Commit**

```bash
git add crates/beansd/src/web/routes/api/projects.rs
git commit -m "beansd: migrate start/stop handlers into web::routes::api::projects"
```
