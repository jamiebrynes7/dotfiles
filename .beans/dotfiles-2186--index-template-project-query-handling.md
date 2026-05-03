---
# dotfiles-2186
title: Index template + `?project=` query handling
status: todo
type: task
created_at: 2026-05-03T14:39:41Z
updated_at: 2026-05-03T14:39:41Z
parent: dotfiles-60yo
---

**Files:**
- Modify: `packages/beans-daemon/src/launcher.rs`
- Create: `packages/beans-daemon/templates/index.html`
- Create: `packages/beans-daemon/templates/project_list.html`
- Modify: `packages/beans-daemon/Cargo.toml` (askama config)

The launcher's main page renders the project list (left nav) plus an iframe panel (main content). If `?project=<encoded-key>` is present and matches a registered project, the iframe loads `http://127.0.0.1:<port>/`; otherwise the panel shows empty state.

- [ ] **Step 1: Set askama template directory**

Append to `packages/beans-daemon/Cargo.toml`:
```toml
[package.metadata.askama]
dirs = ["templates"]
```

- [ ] **Step 2: Author the templates**

`packages/beans-daemon/templates/project_list.html`:
```html
{% for p in projects %}
<a class="project{% if Some(p.key.clone()) == active_key %} active{% endif %}"
   href="/?project={{ p.key.display() }}">
  <div class="name">{{ p.display_name }}</div>
  <div class="meta">
    <span class="badge {{ p.state }}">{{ p.state }}</span>
    {% if let Some(port) = p.port %}<span>:{{ port }}</span>{% endif %}
  </div>
</a>
{% endfor %}
```

`packages/beans-daemon/templates/index.html`:
```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>beans daemon</title>
  <link rel="stylesheet" href="/static/app.css">
  <script src="/static/htmx.min.js"></script>
</head>
<body>
  <nav>
    <h1>Projects</h1>
    <div id="project-list"
         hx-get="/partials/projects?active={% if let Some(k) = active_key %}{{ k.display() }}{% endif %}"
         hx-trigger="every 5s">
      {% include "project_list.html" %}
    </div>
  </nav>
  <main>
    {% if let Some(p) = active_project %}
      <iframe src="http://127.0.0.1:{{ p.port }}/"></iframe>
      <form hx-post="/api/heartbeat" hx-trigger="every 15s" hx-vals='{"key":"{{ p.key.display() }}"}' style="display:none"></form>
    {% else %}
      <div class="empty">
        {% if active_key.is_some() %}
          Not registered — cd into the directory to activate.
        {% else %}
          Select a project from the left.
        {% endif %}
      </div>
    {% endif %}
  </main>
</body>
</html>
```

- [ ] **Step 3: Add the index handler**

Append to `packages/beans-daemon/src/launcher.rs`:
```rust
use askama::Template;
use crate::registry::{Project, Registry};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Clone)]
pub struct LauncherState {
    pub registry: Arc<Mutex<Registry>>,
}

#[derive(Debug)]
struct ProjectView {
    key:          PathBuf,
    display_name: String,
    state:        &'static str,
    port:         Option<u16>,
}

fn project_views(reg: &Registry) -> Vec<ProjectView> {
    use crate::registry::ProjectState;
    reg.iter().map(|p| {
        let (state, port) = match &p.state {
            ProjectState::Spawning { .. } => ("spawning", None),
            ProjectState::Healthy  { port, .. } => ("healthy", Some(*port)),
            ProjectState::Evicting { .. } => ("evicting", None),
            ProjectState::Dead     { .. } => ("dead", None),
        };
        ProjectView {
            key: p.key.clone(),
            display_name: p.display_name.clone(),
            state, port,
        }
    }).collect()
}

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {
    projects:       Vec<ProjectView>,
    active_key:     Option<PathBuf>,
    active_project: Option<ProjectView>,
}

#[derive(serde::Deserialize)]
struct IndexQuery { project: Option<PathBuf> }

async fn index(
    axum::extract::Query(q): axum::extract::Query<IndexQuery>,
    axum::extract::State(state): axum::extract::State<LauncherState>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let projects = project_views(&reg);
    let active_project = q.project.as_ref().and_then(|k| {
        projects.iter().find(|p| &p.key == k && p.port.is_some()).cloned()
    });
    let tmpl = IndexTemplate { projects, active_key: q.project, active_project };
    axum::response::Html(tmpl.render().unwrap())
}

// To make ProjectView Clone:
impl Clone for ProjectView {
    fn clone(&self) -> Self {
        Self { key: self.key.clone(), display_name: self.display_name.clone(), state: self.state, port: self.port }
    }
}

pub fn router_with_state(state: LauncherState) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/static/htmx.min.js", get(serve_htmx))
        .route("/static/app.css",     get(serve_css))
        .with_state(state)
}
```

- [ ] **Step 4: Test the index endpoint**

Append to `mod tests`:
```rust
    use crate::registry::ProjectState;
    use std::time::Instant;

    #[tokio::test]
    async fn index_renders_empty_state() {
        let state = LauncherState { registry: Arc::new(Mutex::new(Registry::new())) };
        let app = router_with_state(state);
        let resp = app.oneshot(Request::get("/").body(axum::body::Body::empty()).unwrap()).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = String::from_utf8(axum::body::to_bytes(resp.into_body(), 64*1024).await.unwrap().to_vec()).unwrap();
        assert!(body.contains("Select a project"));
    }

    #[tokio::test]
    async fn index_with_unknown_project_query_shows_not_registered() {
        let state = LauncherState { registry: Arc::new(Mutex::new(Registry::new())) };
        let app = router_with_state(state);
        let resp = app.oneshot(Request::get("/?project=/tmp/missing").body(axum::body::Body::empty()).unwrap()).await.unwrap();
        let body = String::from_utf8(axum::body::to_bytes(resp.into_body(), 64*1024).await.unwrap().to_vec()).unwrap();
        assert!(body.contains("Not registered"));
    }
```

- [ ] **Step 5: Run tests**

Run: `cargo test launcher::`
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add packages/beans-daemon/src/launcher.rs packages/beans-daemon/templates/ packages/beans-daemon/Cargo.toml packages/beans-daemon/Cargo.lock
git commit -m "packages/beans-daemon: launcher index template with iframe panel"
```
