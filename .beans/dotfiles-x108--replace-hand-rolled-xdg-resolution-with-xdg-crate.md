---
# dotfiles-x108
title: Replace hand-rolled XDG resolution with `xdg` crate
status: completed
type: task
priority: normal
created_at: 2026-05-09T13:43:09Z
updated_at: 2026-05-09T13:44:09Z
parent: dotfiles-rlzx
---

The hand-rolled `Config::default_path` in `packages/beans-daemon/src/config.rs` doesn't fully implement the XDG spec (it accepts an empty `XDG_CONFIG_HOME` rather than ignoring it), and its test mutates a process-wide env var which won't compose if more env-touching tests are added. Replace with the `xdg` crate.

**Files:**
- Modify: `packages/beans-daemon/Cargo.toml` (add `xdg` dep)
- Modify: `packages/beans-daemon/src/config.rs` (rewrite `default_path`, drop env-mutating test)

- [x] **Step 1: Add `xdg` to Cargo.toml**

Add to `[dependencies]`: `xdg = "2"`.

- [x] **Step 2: Rewrite `Config::default_path`**

Replace the current body of `default_path()` with a single call into `xdg::BaseDirectories`, e.g.:
```rust
pub fn default_path() -> anyhow::Result<PathBuf> {
    let dirs = xdg::BaseDirectories::with_prefix("beans-daemon");
    Ok(dirs.get_config_file("config.toml"))
}
```
(Adjust to match the version of the `xdg` crate that resolves; the 2.x API returns `PathBuf`, the 3.x API returns `Option<PathBuf>` and may need a fallback message.)

- [x] **Step 3: Drop the racy env-mutating test**

Delete `default_path_uses_xdg_when_set` from `config::load_tests`. Resolution behaviour is now the `xdg` crate's responsibility — we don't re-test it. Keep the `loads_from_path` and `missing_file_returns_error_with_path` tests.

- [x] **Step 4: Run tests + clippy**

`cargo test config::` and `cargo clippy --all-targets`. Tests should pass; no new warnings.

- [x] **Step 5: Commit**

```bash
git add packages/beans-daemon/Cargo.toml packages/beans-daemon/src/config.rs
git commit -m "packages/beans-daemon: use xdg crate for config path resolution"
```

## Summary of Changes

- Added `xdg = "2"` to `packages/beans-daemon/Cargo.toml` (resolved to 2.5.2).
- Rewrote `Config::default_path` to a 2-line delegation to `xdg::BaseDirectories::with_prefix("beans-daemon")?.get_config_file("config.toml")`. The `?` propagates `BaseDirectoriesError` (returned when neither `XDG_CONFIG_HOME` nor `HOME` is set) into `anyhow::Error`.
- Removed `default_path_uses_xdg_when_set` since resolution is now delegated to a tested upstream crate. The remaining 6 tests pass under `cargo test config::` and clippy emits no new warnings.
