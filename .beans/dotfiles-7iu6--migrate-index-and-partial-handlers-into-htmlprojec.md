---
# dotfiles-7iu6
title: Migrate index and partial handlers into html/projects.rs; add web::test_utils
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:07:44Z
updated_at: 2026-05-24T15:09:15Z
parent: dotfiles-tlhu
blocked_by:
    - dotfiles-ms85
---

**Files:**
- Replace: `crates/beansd/src/web/routes/html/projects.rs` (was a stub from dotfiles-ms85)
- Modify: `crates/beansd/src/web/mod.rs` (append `#[cfg(test)] mod test_utils`)
- Source: copy from `crates/beansd/src/launcher.rs:48-103` (handlers) and `173-315` (tests)

`launcher.rs` keeps its own copy of these handlers and tests until dotfiles-th98 deletes the file. During this task, the binary has duplicates (one set runs through `launcher::router_with_state`, the other through `web::Server`). That's fine because launcher.rs's handlers are the ones wired into `run.rs`.

- [ ] **Step 1: Append `test_utils` to `crates/beansd/src/web/mod.rs`**

Add at the bottom of the file:

```rust
#[cfg(test)]
pub(in crate::web) mod test_utils {
    use super::{router, State};
    use crate::daemon::Daemon;
    use crate::registry::Registry;
    use crate::supervisor::test_utils::FakeSupervisor;
    use std::sync::Arc;
    use tokio::sync::Mutex;

    pub(in crate::web) fn build_state(registry: Arc<Mutex<Registry>>) -> State {
        let supervisor = FakeSupervisor::new(registry.clone());
        let daemon = Arc::new(Daemon {
            registry: registry.clone(),
            supervisor,
            lru_cap: 8,
        });
        State { registry, daemon }
    }

    pub(in crate::web) fn empty_state() -> State {
        build_state(Arc::new(Mutex::new(Registry::new())))
    }

    pub(in crate::web) fn router_with_state(state: State) -> axum::Router {
        router(state)
    }
}
```

`router_with_state` is the test seam: it calls the private `web::router` so route tests can build the full merged `Router` (state-bound) and drive it via `tower::ServiceExt::oneshot` — the same pattern launcher.rs's tests use today.

- [ ] **Step 2: Replace `crates/beansd/src/web/routes/html/projects.rs`**

```rust
use crate::web::views::{project_views, ProjectView};
use crate::web::State;
use askama::Template;
use axum::response::IntoResponse;
use axum::{routing::get, Router};
use std::path::PathBuf;

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {
    projects: Vec<ProjectView>,
    active_key: Option<PathBuf>,
    active_project: Option<ProjectView>,
}

#[derive(serde::Deserialize)]
struct IndexQuery {
    project: Option<PathBuf>,
}

async fn index(
    axum::extract::Query(q): axum::extract::Query<IndexQuery>,
    axum::extract::State(state): axum::extract::State<State>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let projects = project_views(&reg);
    let active_project = q.project.as_ref().and_then(|k| {
        projects
            .iter()
            .find(|p| &p.key == k && p.port.is_some())
            .cloned()
    });
    let tmpl = IndexTemplate {
        projects,
        active_key: q.project,
        active_project,
    };
    axum::response::Html(tmpl.render().unwrap())
}

#[derive(Template)]
#[template(path = "project_list.html")]
pub(in crate::web) struct ProjectListPartial {
    pub(in crate::web) projects: Vec<ProjectView>,
    pub(in crate::web) active_key: Option<PathBuf>,
}

#[derive(serde::Deserialize)]
struct PartialQuery {
    active: Option<PathBuf>,
}

async fn projects_partial(
    axum::extract::Query(q): axum::extract::Query<PartialQuery>,
    axum::extract::State(state): axum::extract::State<State>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: q.active,
    };
    axum::response::Html(tmpl.render().unwrap())
}

pub(super) fn router() -> Router<State> {
    Router::new()
        .route("/", get(index))
        .route("/partials/projects", get(projects_partial))
}

#[cfg(test)]
mod tests {
    use crate::registry::{self, Project, ProjectState, Registry};
    use crate::spawner::testing::FakeChildHandle;
    use crate::web::test_utils::{build_state, empty_state, router_with_state};
    use axum::http::{Request, StatusCode};
    use std::sync::Arc;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    #[tokio::test]
    async fn index_renders_empty_state() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(Request::get("/").body(axum::body::Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = String::from_utf8(
            axum::body::to_bytes(resp.into_body(), 64 * 1024)
                .await
                .unwrap()
                .to_vec(),
        )
        .unwrap();
        assert!(body.contains("Select a project"));
    }

    #[tokio::test]
    async fn partial_returns_ok_for_empty_registry() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/partials/projects")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn partial_lists_registered_projects() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/p".into(),
                "p".into(),
                ProjectState::Healthy {
                    port: 4242,
                    child: Box::new(FakeChildHandle::new(1)),
                },
            )],
        );
        let app = router_with_state(build_state(Arc::new(Mutex::new(r))));
        let resp = app
            .oneshot(
                Request::get("/partials/projects")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = String::from_utf8(
            axum::body::to_bytes(resp.into_body(), 64 * 1024)
                .await
                .unwrap()
                .to_vec(),
        )
        .unwrap();
        assert!(body.contains("healthy"));
        assert!(body.contains(":4242"));
    }

    #[tokio::test]
    async fn index_with_unknown_project_query_shows_not_registered() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/?project=/tmp/missing")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = String::from_utf8(
            axum::body::to_bytes(resp.into_body(), 64 * 1024)
                .await
                .unwrap()
                .to_vec(),
        )
        .unwrap();
        assert!(body.contains("Not registered"));
    }
}
```

`ProjectListPartial` (struct + fields) is `pub(in crate::web)` because `web/routes/api/projects.rs` re-renders it after start/stop.

- [ ] **Step 3: Build and run tests**

```bash
cargo test -p beansd
```

Expected: 12 tests pass — the 8 still in `launcher.rs` plus the 4 new ones in `web::routes::html::projects::tests` (`index_renders_empty_state`, `partial_returns_ok_for_empty_registry`, `partial_lists_registered_projects`, `index_with_unknown_project_query_shows_not_registered`).

- [ ] **Step 4: Commit**

```bash
git add crates/beansd/src/web/routes/html/projects.rs crates/beansd/src/web/mod.rs
git commit -m "beansd: migrate index and project_list handlers into web::routes::html::projects"
```
