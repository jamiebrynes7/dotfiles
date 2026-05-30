---
# dotfiles-n7m9
title: Extract resolve_active helper
status: todo
type: task
created_at: 2026-05-26T20:08:22Z
updated_at: 2026-05-26T20:08:22Z
parent: dotfiles-a93p
---

**Files:**
- Modify: `crates/beansd/src/web/views.rs` (add helper + tests)
- Modify: `crates/beansd/src/web/routes/html/projects.rs:28-33` (use helper in `index`)

- [ ] **Step 1: Add failing test for `resolve_active`**

Append to `crates/beansd/src/web/views.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn view(key: &str, port: Option<u16>) -> ProjectView {
        ProjectView {
            key: PathBuf::from(key),
            display_name: key.into(),
            state: if port.is_some() { "healthy" } else { "dead" },
            port,
        }
    }

    #[test]
    fn resolve_active_returns_match_only_when_port_present() {
        let projects = vec![view("/a", Some(4242)), view("/b", None)];
        let a = PathBuf::from("/a");
        let b = PathBuf::from("/b");
        let missing = PathBuf::from("/c");

        assert!(resolve_active(&projects, Some(&a)).is_some());
        assert!(resolve_active(&projects, Some(&b)).is_none(), "no port -> None");
        assert!(resolve_active(&projects, Some(&missing)).is_none());
        assert!(resolve_active(&projects, None).is_none());
    }
}
```

- [ ] **Step 2: Verify test fails**

Run: `cargo test -p beansd --lib web::views::tests::resolve_active`
Expected: FAIL — `cannot find function resolve_active in module super`

- [ ] **Step 3: Implement `resolve_active`**

Add to `crates/beansd/src/web/views.rs`, above the `#[cfg(test)]` block (and add `use std::path::Path;` next to the existing `use std::path::PathBuf;`):

```rust
pub(in crate::web) fn resolve_active(
    projects: &[ProjectView],
    key: Option<&Path>,
) -> Option<ProjectView> {
    let key = key?;
    projects
        .iter()
        .find(|p| p.key == key && p.port.is_some())
        .cloned()
}
```

- [ ] **Step 4: Verify test passes**

Run: `cargo test -p beansd --lib web::views::tests::resolve_active`
Expected: PASS

- [ ] **Step 5: Use helper from `index` handler**

In `crates/beansd/src/web/routes/html/projects.rs`, replace the body of `async fn index` with:

```rust
async fn index(
    axum::extract::Query(q): axum::extract::Query<IndexQuery>,
    axum::extract::State(state): axum::extract::State<State>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let projects = project_views(&reg);
    let active_project = crate::web::views::resolve_active(&projects, q.project.as_deref());
    let tmpl = IndexTemplate {
        projects,
        active_key: q.project,
        active_project,
    };
    axum::response::Html(tmpl.render().unwrap())
}
```

- [ ] **Step 6: Verify whole crate still compiles & tests pass**

Run: `cargo test -p beansd`
Expected: PASS (all existing tests still green)

- [ ] **Step 7: Commit**

```bash
git add crates/beansd/src/web/views.rs crates/beansd/src/web/routes/html/projects.rs
git commit -m "refactor(beansd): extract resolve_active helper for active project lookup"
```
