---
# dotfiles-jf1c
title: Embed static assets (htmx, app.css) + serve via axum
status: todo
type: task
created_at: 2026-05-03T14:39:41Z
updated_at: 2026-05-03T14:39:41Z
parent: dotfiles-60yo
---

**Files:**
- Create: `packages/beans-daemon/src/launcher.rs`
- Create: `packages/beans-daemon/static/htmx.min.js` (download from https://unpkg.com/htmx.org@1.9.12/dist/htmx.min.js)
- Create: `packages/beans-daemon/static/app.css`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod launcher;`)

- [ ] **Step 1: Vendor the htmx asset**

```bash
mkdir -p packages/beans-daemon/static
curl -fsSL https://unpkg.com/htmx.org@1.9.12/dist/htmx.min.js -o packages/beans-daemon/static/htmx.min.js
```

Verify the file size is around 14 KB and is non-empty.

- [ ] **Step 2: Write minimal CSS**

`packages/beans-daemon/static/app.css`:
```css
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; height: 100vh; display: grid; grid-template-columns: 280px 1fr; }
nav { background: #1e1e2e; color: #cdd6f4; padding: 1rem; overflow-y: auto; }
nav h1 { font-size: 0.9rem; opacity: 0.6; margin-bottom: 1rem; text-transform: uppercase; }
nav .project { display: block; padding: 0.5rem; border-radius: 4px; cursor: pointer; color: inherit; text-decoration: none; }
nav .project:hover { background: #313244; }
nav .project.active { background: #45475a; }
nav .project .name { font-weight: 500; }
nav .project .meta { font-size: 0.75rem; opacity: 0.6; }
nav .badge { display: inline-block; font-size: 0.65rem; padding: 0.1rem 0.4rem; border-radius: 4px; margin-left: 0.3rem; }
nav .badge.healthy  { background: #a6e3a1; color: #1e1e2e; }
nav .badge.spawning { background: #f9e2af; color: #1e1e2e; }
nav .badge.dead     { background: #f38ba8; color: #1e1e2e; }
main { display: flex; flex-direction: column; }
main iframe { flex: 1; border: none; width: 100%; }
main .empty { display: flex; align-items: center; justify-content: center; height: 100%; opacity: 0.5; }
```

- [ ] **Step 3: Write the failing test**

Create `packages/beans-daemon/src/launcher.rs`:
```rust
use axum::{routing::get, Router};
use axum::response::IntoResponse;
use axum::http::header;

const HTMX_JS:  &[u8] = include_bytes!("../static/htmx.min.js");
const APP_CSS:  &str  = include_str!("../static/app.css");

async fn serve_htmx() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript")], HTMX_JS)
}
async fn serve_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css")], APP_CSS)
}

pub fn router() -> Router {
    Router::new()
        .route("/static/htmx.min.js", get(serve_htmx))
        .route("/static/app.css",     get(serve_css))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn serves_htmx_with_js_content_type() {
        let app = router();
        let resp = app.oneshot(Request::get("/static/htmx.min.js").body(axum::body::Body::empty()).unwrap()).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(resp.headers().get("content-type").unwrap(), "application/javascript");
    }

    #[tokio::test]
    async fn serves_css_with_css_content_type() {
        let app = router();
        let resp = app.oneshot(Request::get("/static/app.css").body(axum::body::Body::empty()).unwrap()).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(resp.headers().get("content-type").unwrap(), "text/css");
    }
}
```

Add to `Cargo.toml` `[dev-dependencies]`:
```toml
tower = "0.4"
```

- [ ] **Step 4: Wire into main.rs and run tests**

Add `mod launcher;`. Run: `cargo test launcher::`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/launcher.rs packages/beans-daemon/src/main.rs packages/beans-daemon/static/ packages/beans-daemon/Cargo.toml packages/beans-daemon/Cargo.lock
git commit -m "packages/beans-daemon: launcher static asset serving (htmx + css)"
```
