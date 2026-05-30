---
# dotfiles-x9za
title: Top bar templates, struct rename, and route
status: completed
type: task
priority: normal
created_at: 2026-05-26T20:21:14Z
updated_at: 2026-05-30T15:54:16Z
parent: dotfiles-a93p
blocked_by:
    - dotfiles-n7m9
---

**Files:**
- Create: `crates/beansd/src/web/templates/top_bar.html`
- Modify: `crates/beansd/src/web/templates/index.html` (replace `<nav>` block with `<header>`; update empty-state copy)
- Delete: `crates/beansd/src/web/templates/project_list.html`
- Modify: `crates/beansd/src/web/routes/html/projects.rs` (struct, route, tests)

**Depends on:** Task `dotfiles-n7m9` (uses `crate::web::views::resolve_active`)

- [x] **Step 1: Create `top_bar.html`**

Write `crates/beansd/src/web/templates/top_bar.html`:

```html
<details class="project-switcher">
  <summary>
    {% if let Some(p) = active_project %}{{ p.display_name }}{% else %}Select a project{% endif %}
    <span class="caret">▾</span>
  </summary>
  <div class="panel">
    {% for p in projects %}
    <a class="project-row{% if Some(p.key.clone()) == active_key %} active{% endif %}"
       href="/?project={{ p.key.display() }}">
      <div class="name">{{ p.display_name }}</div>
      <div class="path">{{ p.key.display() }}</div>
      <span class="badge {{ p.state }}">{{ p.state }}</span>
    </a>
    {% endfor %}
  </div>
</details>
{% if let Some(p) = active_project %}
<div class="topbar-detail">
  <span class="badge {{ p.state }}">{{ p.state }}</span>
  <span class="path">{{ p.key.display() }}</span>
  {% if let Some(port) = p.port %}<span class="port">:{{ port }}</span>{% endif %}
</div>
{% endif %}
```

- [x] **Step 2: Replace `index.html`**

Overwrite `crates/beansd/src/web/templates/index.html` with:

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
  <header id="topbar"
          hx-get="/partials/topbar?active={% if let Some(k) = active_key %}{{ k.display() }}{% endif %}"
          hx-trigger="every 5s">
    {% include "top_bar.html" %}
  </header>
  <main>
    {% if let Some(p) = active_project %}
      <iframe src="http://127.0.0.1:{{ p.port.unwrap() }}/"></iframe>
      <form hx-post="/api/heartbeat" hx-trigger="every 15s" hx-vals='{"key":"{{ p.key.display() }}"}' style="display:none"></form>
    {% else %}
      <div class="empty">
        {% if active_key.is_some() %}
          Not registered — cd into the directory to activate.
        {% else %}
          No active project.
        {% endif %}
      </div>
    {% endif %}
  </main>
</body>
</html>
```

- [x] **Step 3: Rename struct, change template path, add field, rename route**

In `crates/beansd/src/web/routes/html/projects.rs`, replace the existing `ProjectListPartial` struct + `projects_partial` handler + `router` with:

```rust
#[derive(Template)]
#[template(path = "top_bar.html")]
pub(in crate::web) struct TopBarPartial {
    pub(in crate::web) projects: Vec<ProjectView>,
    pub(in crate::web) active_key: Option<PathBuf>,
    pub(in crate::web) active_project: Option<ProjectView>,
}

async fn topbar_partial(
    axum::extract::Query(q): axum::extract::Query<PartialQuery>,
    axum::extract::State(state): axum::extract::State<State>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let projects = project_views(&reg);
    let active_project = crate::web::views::resolve_active(&projects, q.active.as_deref());
    let tmpl = TopBarPartial {
        projects,
        active_key: q.active,
        active_project,
    };
    axum::response::Html(tmpl.render().unwrap())
}

pub(super) fn router() -> Router<State> {
    Router::new()
        .route("/", get(index))
        .route("/partials/topbar", get(topbar_partial))
}
```

- [x] **Step 4: Delete `project_list.html`**

```bash
rm crates/beansd/src/web/templates/project_list.html
```

- [x] **Step 5: Update existing tests**

In the `#[cfg(test)] mod tests` block of `projects.rs`:

In `index_renders_empty_state`, change the assertion to:

```rust
assert!(body.contains("No active project"));
```

In `partial_returns_ok_for_empty_registry`, change the request line to:

```rust
.oneshot(
    Request::get("/partials/topbar")
        .body(axum::body::Body::empty())
        .unwrap(),
)
```

In `partial_lists_registered_projects`, change the same `Request::get(...)` line to `"/partials/topbar"`, and replace the two trailing asserts with:

```rust
assert!(body.contains("healthy"));
assert!(body.contains("/tmp/p"), "path should appear in the dropdown row");
```

(The `:4242` assertion moves to the new detail-strip test in step 6 — it is only rendered when `active_project` is `Some`, which the partial test does not set.)

- [x] **Step 6: Add detail-strip test**

Append inside the `#[cfg(test)] mod tests` block:

```rust
#[tokio::test]
async fn index_with_active_project_shows_detail_strip() {
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
    let app = router().with_state(build_state(Arc::new(Mutex::new(r))));
    let resp = app
        .oneshot(
            Request::get("/?project=/tmp/p")
                .body(axum::body::Body::empty())
                .unwrap(),
        )
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
    assert!(body.contains(":4242"), "port should appear in detail strip");
    let path_count = body.matches("/tmp/p").count();
    assert!(
        path_count >= 2,
        "path should appear in both row and detail strip, got {path_count}"
    );
}
```

- [x] **Step 7: Run all tests**

Run: `cargo test -p beansd`
Expected: PASS (renamed tests now hit `/partials/topbar`; new detail-strip test passes; no leftover references to `project_list.html` or `ProjectListPartial`).

- [x] **Step 8: Commit**

```bash
git add crates/beansd/src/web/templates/top_bar.html \
        crates/beansd/src/web/templates/index.html \
        crates/beansd/src/web/routes/html/projects.rs
git add -u crates/beansd/src/web/templates/project_list.html
git commit -m "refactor(beansd): replace sidebar with top-bar dropdown UI"
```

(`git add -u` picks up the deletion of `project_list.html`.)

## Summary of Changes

Created `top_bar.html` (dropdown switcher + active-project detail strip), rewrote `index.html` to host a `<header id="topbar">` polling `/partials/topbar` (heartbeat form kept in `<main>`), deleted `project_list.html`, and renamed `ProjectListPartial`/`projects_partial`/`/partials/projects` to `TopBarPartial`/`topbar_partial`/`/partials/topbar` with the added `active_project` field. Updated existing tests to the new route/copy and added `index_with_active_project_shows_detail_strip`. All 39 beansd tests pass.
