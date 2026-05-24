---
# dotfiles-flje
title: Create web/views.rs with ProjectView and project_views
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:06:48Z
updated_at: 2026-05-24T15:09:13Z
parent: dotfiles-j2qx
blocked_by:
    - dotfiles-c7ss
---

**Files:**
- Create: `crates/beansd/src/web/views.rs`
- Modify: `crates/beansd/src/web/mod.rs` (declare `mod views;`)
- Source: copy from `crates/beansd/src/launcher.rs:20-46` (originals stay in launcher.rs; deleted in dotfiles-th98)

- [ ] **Step 1: Create `crates/beansd/src/web/views.rs`**

```rust
use crate::registry::Registry;
use std::path::PathBuf;

#[derive(Clone)]
pub(in crate::web) struct ProjectView {
    pub(in crate::web) key: PathBuf,
    pub(in crate::web) display_name: String,
    pub(in crate::web) state: &'static str,
    pub(in crate::web) port: Option<u16>,
}

pub(in crate::web) fn project_views(reg: &Registry) -> Vec<ProjectView> {
    use crate::registry::ProjectState;
    reg.iter()
        .map(|p| {
            let (state, port) = match &p.state {
                ProjectState::Spawning { .. } => ("spawning", None),
                ProjectState::Healthy { port, .. } => ("healthy", Some(*port)),
                ProjectState::Evicting { .. } => ("evicting", None),
                ProjectState::Dead { .. } => ("dead", None),
            };
            ProjectView {
                key: p.key.clone(),
                display_name: p.display_name.clone(),
                state,
                port,
            }
        })
        .collect()
}
```

Fields are `pub(in crate::web)` because the askama template structs in `web/routes/html/projects.rs` read them when rendering.

- [ ] **Step 2: Declare `mod views;` in `web/mod.rs`**

Add immediately after the `use` block:

```rust
mod views;
```

- [ ] **Step 3: Verify the crate builds**

```bash
cargo build -p beansd
```

Expected: clean build. `dead_code` warnings on `ProjectView` / `project_views` are expected — dotfiles-tlhu's task imports them.

- [ ] **Step 4: Run tests**

```bash
cargo test -p beansd
```

Expected: all 8 launcher tests still pass.

- [ ] **Step 5: Commit**

```bash
git add crates/beansd/src/web/views.rs crates/beansd/src/web/mod.rs
git commit -m "beansd: add ProjectView and project_views in web::views"
```
