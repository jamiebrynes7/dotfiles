---
# dotfiles-gzr8
title: Migrate heartbeat handler into api/heartbeat.rs
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:08:11Z
updated_at: 2026-05-24T15:09:17Z
parent: dotfiles-p6a4
blocked_by:
    - dotfiles-7iu6
---

**Files:**
- Replace: `crates/beansd/src/web/routes/api/heartbeat.rs` (was a stub from dotfiles-ms85)
- Source: copy from `crates/beansd/src/launcher.rs:110-119` (handler) and `317-356` (test)

- [ ] **Step 1: Replace `crates/beansd/src/web/routes/api/heartbeat.rs`**

```rust
use crate::web::routes::api::KeyForm;
use crate::web::State;
use axum::response::IntoResponse;
use axum::{routing::post, Router};

async fn heartbeat(
    axum::extract::State(state): axum::extract::State<State>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    use beansd_rpc::Handler;
    match state.daemon.heartbeat(f.key).await {
        Ok(()) => axum::http::StatusCode::NO_CONTENT,
        Err(_) => axum::http::StatusCode::INTERNAL_SERVER_ERROR,
    }
}

pub(super) fn router() -> Router<State> {
    Router::new().route("/api/heartbeat", post(heartbeat))
}

#[cfg(test)]
mod tests {
    use crate::registry::{self, Project, ProjectState, Registry};
    use crate::web::test_utils::{build_state, router_with_state};
    use axum::http::{Request, StatusCode};
    use std::path::Path;
    use std::sync::Arc;
    use std::time::Duration;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    #[tokio::test]
    async fn heartbeat_returns_204_and_bumps_last_used() {
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
        let before = registry
            .lock()
            .await
            .get(Path::new("/tmp/x"))
            .unwrap()
            .last_used;
        tokio::time::sleep(Duration::from_millis(20)).await;

        let app = router_with_state(build_state(registry.clone()));
        let resp = app
            .oneshot(
                Request::post("/api/heartbeat")
                    .header("content-type", "application/x-www-form-urlencoded")
                    .body(axum::body::Body::from("key=/tmp/x"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NO_CONTENT);

        let after = registry
            .lock()
            .await
            .get(Path::new("/tmp/x"))
            .unwrap()
            .last_used;
        assert!(after > before);
    }
}
```

Dependencies:
- `crate::web::routes::api::KeyForm` from `api/mod.rs` (created in dotfiles-ms85).
- `crate::web::test_utils::{build_state, router_with_state}` (added in dotfiles-tlhu).

- [ ] **Step 2: Build and run tests**

```bash
cargo test -p beansd
```

Expected: 14 tests pass — 8 launcher + 4 html + 1 api/projects + 1 new `web::routes::api::heartbeat::tests::heartbeat_returns_204_and_bumps_last_used`.

- [ ] **Step 3: Commit**

```bash
git add crates/beansd/src/web/routes/api/heartbeat.rs
git commit -m "beansd: migrate heartbeat handler into web::routes::api::heartbeat"
```
