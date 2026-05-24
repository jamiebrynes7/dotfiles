---
# dotfiles-tlpb
title: Move templates, static, askama.toml; fix include paths
status: todo
type: task
created_at: 2026-05-24T15:06:21Z
updated_at: 2026-05-24T15:06:21Z
parent: dotfiles-4jzf
---

**Files:**
- Move: `crates/beansd/templates/` → `crates/beansd/src/web/templates/`
- Move: `crates/beansd/static/` → `crates/beansd/src/web/static/`
- Create: `crates/beansd/askama.toml`
- Modify: `crates/beansd/src/launcher.rs` lines 11-12 (interim — file is deleted in dotfiles-th98)

This is a refactor — no new behavior, no new tests. Verification is that the existing 8 tests in `launcher.rs` still pass after the move.

- [ ] **Step 1: Move templates directory**

```bash
mkdir -p crates/beansd/src/web
git mv crates/beansd/templates crates/beansd/src/web/templates
```

- [ ] **Step 2: Move static directory**

```bash
git mv crates/beansd/static crates/beansd/src/web/static
```

- [ ] **Step 3: Create `crates/beansd/askama.toml`**

```toml
[general]
dirs = ["src/web/templates"]
```

Askama 0.12 reads this file from `CARGO_MANIFEST_DIR`; `dirs` overrides the default `["templates"]`. After this, `#[template(path = "index.html")]` in `launcher.rs` resolves to `crates/beansd/src/web/templates/index.html`.

- [ ] **Step 4: Update `include_*!` paths in `crates/beansd/src/launcher.rs`**

`launcher.rs` lives at `crates/beansd/src/launcher.rs`. From its perspective, the new static dir is `web/static/` (no `..` needed — it's a sibling subtree).

Replace:
```rust
const HTMX_JS: &[u8] = include_bytes!("../static/htmx.min.js");
const APP_CSS: &str = include_str!("../static/app.css");
```
with:
```rust
const HTMX_JS: &[u8] = include_bytes!("web/static/htmx.min.js");
const APP_CSS: &str = include_str!("web/static/app.css");
```

(These get removed in dotfiles-th98 when `launcher.rs` is deleted; this is an interim fix to keep the crate building.)

- [ ] **Step 5: Verify build and tests**

```bash
cargo test -p beansd
```

Expected: all 8 launcher tests pass (`serves_htmx_with_js_content_type`, `serves_css_with_css_content_type`, `index_renders_empty_state`, `partial_returns_ok_for_empty_registry`, `partial_lists_registered_projects`, `index_with_unknown_project_query_shows_not_registered`, `heartbeat_returns_204_and_bumps_last_used`, `stop_returns_partial_html`).

If askama complains "template not found", confirm `askama.toml` lives at `crates/beansd/askama.toml` and that `dirs = ["src/web/templates"]` (relative to the crate, not the workspace).

- [ ] **Step 6: Commit**

```bash
git add crates/beansd/src/web crates/beansd/askama.toml crates/beansd/src/launcher.rs
git commit -m "beansd: relocate templates and static under src/web/"
```
