---
# dotfiles-btt9
title: Validate `beans_serve_path` points to an executable
status: todo
type: task
created_at: 2026-05-03T14:33:45Z
updated_at: 2026-05-03T14:33:45Z
parent: dotfiles-rlzx
---

**Files:**
- Modify: `packages/beans-daemon/src/config.rs`

- [ ] **Step 1: Write the failing test**

Append to the existing `mod load_tests` block:
```rust
    #[test]
    fn validate_passes_for_executable() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempdir().unwrap();
        let bin = dir.path().join("fake-beans-serve");
        std::fs::write(&bin, "#!/bin/sh\nexit 0\n").unwrap();
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        let cfg = Config {
            launcher_port:    9000,
            lru_cap:          8,
            heartbeat_secs:   15,
            log_level:        "info".into(),
            beans_serve_path: bin,
        };
        cfg.validate().unwrap();
    }

    #[test]
    fn validate_fails_for_missing_file() {
        let cfg = Config {
            launcher_port:    9000,
            lru_cap:          8,
            heartbeat_secs:   15,
            log_level:        "info".into(),
            beans_serve_path: PathBuf::from("/no/such/binary"),
        };
        let err = cfg.validate().unwrap_err();
        assert!(err.to_string().contains("beans_serve_path"));
        assert!(err.to_string().contains("/no/such/binary"));
    }

    #[test]
    fn validate_fails_for_non_executable() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempdir().unwrap();
        let f = dir.path().join("not-executable");
        std::fs::write(&f, "data").unwrap();
        std::fs::set_permissions(&f, std::fs::Permissions::from_mode(0o644)).unwrap();
        let cfg = Config {
            launcher_port:    9000,
            lru_cap:          8,
            heartbeat_secs:   15,
            log_level:        "info".into(),
            beans_serve_path: f,
        };
        let err = cfg.validate().unwrap_err();
        assert!(err.to_string().contains("not executable"));
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test config::load_tests::validate`
Expected: FAIL — `Config::validate` doesn't exist.

- [ ] **Step 3: Implement `validate`**

Add to the `impl Config` block in `packages/beans-daemon/src/config.rs`:
```rust
    /// Sanity-check the loaded config. Currently: ensure `beans_serve_path`
    /// exists and is executable.
    pub fn validate(&self) -> anyhow::Result<()> {
        use std::os::unix::fs::PermissionsExt;
        let meta = std::fs::metadata(&self.beans_serve_path).map_err(|e| {
            anyhow::anyhow!("beans_serve_path {} unreadable: {e}", self.beans_serve_path.display())
        })?;
        if !meta.is_file() {
            anyhow::bail!("beans_serve_path {} is not a file", self.beans_serve_path.display());
        }
        if meta.permissions().mode() & 0o111 == 0 {
            anyhow::bail!("beans_serve_path {} is not executable", self.beans_serve_path.display());
        }
        Ok(())
    }
```

- [ ] **Step 4: Run tests**

Run: `cargo test config::`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/config.rs
git commit -m "packages/beans-daemon: validate beans_serve_path is executable"
```
