---
# dotfiles-n25o
title: Migrate static asset handlers into assets.rs
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:08:23Z
updated_at: 2026-05-24T15:09:17Z
parent: dotfiles-prsi
blocked_by:
    - dotfiles-7iu6
---

**Files:**
- Replace: `crates/beansd/src/web/routes/assets.rs` (was a stub from dotfiles-ms85)
- Source: copy from `crates/beansd/src/launcher.rs:11-12` (consts), `153-159` (handlers), `197-228` (tests)

The `include_*!` paths in `assets.rs` are different from those in `launcher.rs` because `assets.rs` lives one level deeper:
- `launcher.rs` (post-dotfiles-tlpb): `include_bytes!("web/static/htmx.min.js")`
- `assets.rs`: `include_bytes!("../static/htmx.min.js")` — up out of `routes/`, into `static/`.

- [ ] **Step 1: Replace `crates/beansd/src/web/routes/assets.rs`**

```rust
use axum::http::header;
use axum::response::IntoResponse;
use axum::{routing::get, Router};

const HTMX_JS: &[u8] = include_bytes!("../static/htmx.min.js");
const APP_CSS: &str = include_str!("../static/app.css");

async fn serve_htmx() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript")], HTMX_JS)
}

async fn serve_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css")], APP_CSS)
}

pub(super) fn router() -> Router<crate::web::State> {
    Router::new()
        .route("/static/htmx.min.js", get(serve_htmx))
        .route("/static/app.css", get(serve_css))
}

#[cfg(test)]
mod tests {
    use crate::web::test_utils::{empty_state, router_with_state};
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn serves_htmx_with_js_content_type() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/static/htmx.min.js")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers().get("content-type").unwrap(),
            "application/javascript"
        );
    }

    #[tokio::test]
    async fn serves_css_with_css_content_type() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/static/app.css")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(resp.headers().get("content-type").unwrap(), "text/css");
    }
}
```

Dependencies:
- `crate::web::test_utils::{empty_state, router_with_state}` (added in dotfiles-tlhu).

- [ ] **Step 2: Build and run tests**

```bash
cargo test -p beansd
```

Expected: 16 tests pass — 8 launcher + 4 html + 1 api/projects + 1 api/heartbeat + 2 new asset tests (`serves_htmx_with_js_content_type`, `serves_css_with_css_content_type`).

- [ ] **Step 3: Commit**

```bash
git add crates/beansd/src/web/routes/assets.rs
git commit -m "beansd: migrate static asset handlers into web::routes::assets"
```
