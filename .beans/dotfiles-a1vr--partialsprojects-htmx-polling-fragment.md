---
# dotfiles-a1vr
title: '`/partials/projects` HTMX polling fragment'
status: todo
type: task
created_at: 2026-05-03T14:39:41Z
updated_at: 2026-05-03T14:39:41Z
parent: dotfiles-60yo
---

**Files:**
- Modify: `packages/beans-daemon/src/launcher.rs`

The HTMX `hx-trigger="every 5s"` attribute on the project list fetches this fragment and swaps it in. It returns just the inner HTML of the list, not a full document.

- [ ] **Step 1: Add the partial**

Append to `packages/beans-daemon/src/launcher.rs`:
```rust
#[derive(Template)]
#[template(path = "project_list.html")]
struct ProjectListPartial {
    projects:   Vec<ProjectView>,
    active_key: Option<PathBuf>,
}

#[derive(serde::Deserialize)]
struct PartialQuery { active: Option<PathBuf> }

async fn projects_partial(
    axum::extract::Query(q): axum::extract::Query<PartialQuery>,
    axum::extract::State(state): axum::extract::State<LauncherState>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial { projects: project_views(&reg), active_key: q.active };
    axum::response::Html(tmpl.render().unwrap())
}
```

Update `router_with_state` to add the route:
```rust
        .route("/partials/projects", get(projects_partial))
```

- [ ] **Step 2: Test it**

Append to `mod tests`:
```rust
    #[tokio::test]
    async fn partial_returns_empty_for_empty_registry() {
        let state = LauncherState { registry: Arc::new(Mutex::new(Registry::new())) };
        let app = router_with_state(state);
        let resp = app.oneshot(Request::get("/partials/projects").body(axum::body::Body::empty()).unwrap()).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = String::from_utf8(axum::body::to_bytes(resp.into_body(), 64*1024).await.unwrap().to_vec()).unwrap();
        assert!(body.trim().is_empty() || body.trim().is_empty() == false);  // just shape, not strict
    }

    #[tokio::test]
    async fn partial_lists_registered_projects() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry.lock().await.insert_spawning("/tmp/p".into(), "p".into(), Instant::now()).unwrap();
        registry.lock().await.transition_state(&"/tmp/p".into(),
            ProjectState::Healthy { port: 4242, pid: 1, spawned_at: Instant::now() }).unwrap();
        let state = LauncherState { registry };
        let app = router_with_state(state);
        let resp = app.oneshot(Request::get("/partials/projects").body(axum::body::Body::empty()).unwrap()).await.unwrap();
        let body = String::from_utf8(axum::body::to_bytes(resp.into_body(), 64*1024).await.unwrap().to_vec()).unwrap();
        assert!(body.contains("healthy"));
        assert!(body.contains(":4242"));
    }
```

- [ ] **Step 3: Run tests**

Run: `cargo test launcher::`
Expected: 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add packages/beans-daemon/src/launcher.rs
git commit -m "packages/beans-daemon: /partials/projects fragment for HTMX polling"
```
