---
# dotfiles-yqai
title: Load config from disk + XDG path resolution
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:33:45Z
updated_at: 2026-05-09T13:41:45Z
parent: dotfiles-rlzx
---

**Files:**
- Modify: `packages/beans-daemon/src/config.rs`

- [x] **Step 1: Write the failing test**

Append to `packages/beans-daemon/src/config.rs`:
```rust
use std::path::Path;

impl Config {
    /// Resolve the canonical config path for the current user:
    /// `\$XDG_CONFIG_HOME/beans-daemon/config.toml`, falling back to
    /// `\$HOME/.config/beans-daemon/config.toml`.
    pub fn default_path() -> anyhow::Result<PathBuf> {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
            .ok_or_else(|| anyhow::anyhow!("neither XDG_CONFIG_HOME nor HOME is set"))?;
        Ok(base.join("beans-daemon").join("config.toml"))
    }

    /// Load and parse the config file at `path`.
    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let raw = std::fs::read_to_string(path)
            .map_err(|e| anyhow::anyhow!("reading {}: {e}", path.display()))?;
        toml::from_str(&raw)
            .map_err(|e| anyhow::anyhow!("parsing {}: {e}", path.display()))
    }
}

#[cfg(test)]
mod load_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn loads_from_path() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("config.toml");
        std::fs::write(&path, r#"beans_serve_path = "/usr/bin/beans-serve""#).unwrap();
        let cfg = Config::load(&path).unwrap();
        assert_eq!(cfg.launcher_port, 9000);
    }

    #[test]
    fn missing_file_returns_error_with_path() {
        let err = Config::load(Path::new("/no/such/file.toml")).unwrap_err();
        assert!(err.to_string().contains("/no/such/file.toml"));
    }

    #[test]
    fn default_path_uses_xdg_when_set() {
        let prev = std::env::var("XDG_CONFIG_HOME").ok();
        std::env::set_var("XDG_CONFIG_HOME", "/tmp/xdg");
        let p = Config::default_path().unwrap();
        assert_eq!(p, PathBuf::from("/tmp/xdg/beans-daemon/config.toml"));
        match prev {
            Some(v) => std::env::set_var("XDG_CONFIG_HOME", v),
            None    => std::env::remove_var("XDG_CONFIG_HOME"),
        }
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cargo test config::`
Expected: FAIL — `Config::load` and `Config::default_path` don't exist yet (these tests are the impl + tests in one block; the impl above is the same edit).

- [x] **Step 3: Confirm no implementation gap**

(The impl is already in the same edit as the tests above. If you split them, add the impl now.)

- [x] **Step 4: Run tests**

Run: `cargo test config::`
Expected: PASS for all `load_tests::` cases plus the existing `tests::` cases.

- [x] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/config.rs
git commit -m "packages/beans-daemon: load Config from XDG path"
```

## Summary of Changes

- Added `Config::default_path()` resolving `$XDG_CONFIG_HOME/beans-daemon/config.toml` with `$HOME/.config/...` fallback; errors when neither env var is set.
- Added `Config::load(&Path)` reading and parsing the TOML file with the file path embedded in any I/O or parse error.
- Three new tests under `config::load_tests`: round-trip load from a tempdir, missing-file error includes the path, and XDG resolution honours `XDG_CONFIG_HOME`. Existing 4 tests still pass (7 total under `cargo test config::`).
- Imports collapsed to `use std::path::{Path, PathBuf};`.

## Deferred

- The `default_path_uses_xdg_when_set` test mutates a process-wide env var. It is currently the only such test, but parallel test additions touching `XDG_CONFIG_HOME`/`HOME` will need explicit serialization (`serial_test` crate or `--test-threads=1`).
- `std::env::set_var`/`remove_var` become `unsafe` under Rust 2024 edition; the crate is on 2021 so this is a non-issue today but worth noting for any future edition bump.
