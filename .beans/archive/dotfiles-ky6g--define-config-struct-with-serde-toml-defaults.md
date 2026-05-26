---
# dotfiles-ky6g
title: Define `Config` struct with serde + toml + defaults
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:33:45Z
updated_at: 2026-05-09T13:40:05Z
parent: dotfiles-rlzx
---

**Files:**
- Create: `packages/beans-daemon/src/config.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod config;`)

- [x] **Step 1: Write the failing test**

Create `packages/beans-daemon/src/config.rs`:
```rust
use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    #[serde(default = "defaults::launcher_port")]
    pub launcher_port: u16,
    #[serde(default = "defaults::lru_cap")]
    pub lru_cap: usize,
    #[serde(default = "defaults::heartbeat_secs")]
    pub heartbeat_secs: u64,
    #[serde(default = "defaults::log_level")]
    pub log_level: String,
    /// Absolute path to the `beans-serve` binary.
    /// Required — rendered by the home-manager module.
    pub beans_serve_path: PathBuf,
}

mod defaults {
    pub fn launcher_port()  -> u16    { 9000 }
    pub fn lru_cap()        -> usize  { 8 }
    pub fn heartbeat_secs() -> u64    { 15 }
    pub fn log_level()      -> String { "info".into() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_config() {
        let toml = r#"beans_serve_path = "/usr/bin/beans-serve""#;
        let cfg: Config = toml::from_str(toml).unwrap();
        assert_eq!(cfg.launcher_port, 9000);
        assert_eq!(cfg.lru_cap, 8);
        assert_eq!(cfg.heartbeat_secs, 15);
        assert_eq!(cfg.log_level, "info");
        assert_eq!(cfg.beans_serve_path, PathBuf::from("/usr/bin/beans-serve"));
    }

    #[test]
    fn parses_full_config() {
        let toml = r#"
launcher_port    = 9100
lru_cap          = 4
heartbeat_secs   = 30
log_level        = "debug"
beans_serve_path = "/nix/store/x/bin/beans-serve"
"#;
        let cfg: Config = toml::from_str(toml).unwrap();
        assert_eq!(cfg.launcher_port, 9100);
        assert_eq!(cfg.lru_cap, 4);
    }

    #[test]
    fn missing_beans_serve_path_errors() {
        let toml = r#"launcher_port = 9000"#;
        let err = toml::from_str::<Config>(toml).unwrap_err();
        assert!(err.to_string().contains("beans_serve_path"));
    }

    #[test]
    fn unknown_field_errors() {
        let toml = r#"
beans_serve_path = "/usr/bin/beans-serve"
launcher_prot    = 9000
"#;
        assert!(toml::from_str::<Config>(toml).is_err());
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cargo test`
Expected: FAIL — `mod config` not declared.

- [x] **Step 3: Wire into main.rs**

Add `mod config;` near the top of `packages/beans-daemon/src/main.rs`.

- [x] **Step 4: Run tests**

Run: `cargo test config::`
Expected: 4 tests pass.

- [x] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/config.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: Config struct with serde defaults"
```

## Summary of Changes

- Added `packages/beans-daemon/src/config.rs` defining the `Config` struct with `serde(deny_unknown_fields)` and defaults (`launcher_port=9000`, `lru_cap=8`, `heartbeat_secs=15`, `log_level="info"`); `beans_serve_path` is required.
- Wired `mod config;` into `packages/beans-daemon/src/main.rs`.
- Four unit tests cover: minimal config + defaults, full config parsing, missing required field, and rejection of unknown fields. All passing under `cargo test config::`.
