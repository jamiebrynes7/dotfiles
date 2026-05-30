---
# dotfiles-m8nc
title: Make beans_serve_path optional with $PATH fallback
status: todo
type: task
priority: normal
created_at: 2026-05-30T18:32:43Z
updated_at: 2026-05-30T18:33:45Z
parent: dotfiles-i5zy
blocked_by:
    - dotfiles-uc8x
---

Make `beans_serve_path` optional. When set (prod, rendered by home-manager) use it verbatim; when omitted (dev config) resolve `beans-serve` from `$PATH` via the `which` crate so the dev config never goes stale against nix-store churn. `validate()` and the spawner both use the *resolved* path.

**Files:**
- Modify: `crates/beansd/src/config.rs` (field, `resolve_beans_serve()`, `validate()`, existing tests)
- Modify: `crates/beansd/src/run.rs:27-29` (spawner uses resolved path)
- Test: `crates/beansd/src/config.rs` (colocated test modules)

- [ ] **Step 1: Write the failing tests**

Add to the `mod load_tests` (it already imports `tempfile::tempdir` and `super::*`) in `crates/beansd/src/config.rs`:

```rust
#[test]
fn resolve_uses_explicit_path_when_set() {
    let cfg = Config {
        launcher_port: 9000,
        lru_cap: 8,
        heartbeat_secs: 15,
        log_level: "info".into(),
        beans_serve_path: Some(PathBuf::from("/explicit/beans-serve")),
    };
    assert_eq!(cfg.resolve_beans_serve().unwrap(), PathBuf::from("/explicit/beans-serve"));
}

#[test]
fn resolve_finds_beans_serve_on_path() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempdir().unwrap();
    let bin = dir.path().join("beans-serve");
    std::fs::write(&bin, "#!/bin/sh
exit 0
").unwrap();
    std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
    let old = std::env::var("PATH").unwrap_or_default();
    std::env::set_var("PATH", format!("{}:{old}", dir.path().display()));
    let cfg = Config {
        launcher_port: 9000, lru_cap: 8, heartbeat_secs: 15,
        log_level: "info".into(), beans_serve_path: None,
    };
    let resolved = cfg.resolve_beans_serve();
    std::env::set_var("PATH", old); // restore before asserting
    assert_eq!(resolved.unwrap(), bin);
}
```

- [ ] **Step 2: Run them, expect failure**

Run: `cargo test -p beansd resolve_`
Expected: FAILS to compile — `beans_serve_path` is not `Option`, `resolve_beans_serve` does not exist.

- [ ] **Step 3: Make the field optional**

In `crates/beansd/src/config.rs`, change the struct field from:

```rust
    /// Absolute path to the `beans-serve` binary.
    /// Required — rendered by the home-manager module.
    pub beans_serve_path: PathBuf,
```

to:

```rust
    /// Absolute path to the `beans-serve` binary. Set by the home-manager
    /// module in prod; omitted in dev-config.toml, where it's resolved from
    /// `$PATH` (see `resolve_beans_serve`).
    pub beans_serve_path: Option<PathBuf>,
```

(Serde treats an `Option` field as optional automatically, so a missing key now yields `None` instead of erroring.)

- [ ] **Step 4: Add `resolve_beans_serve` and route `validate` through it**

In the `impl Config` block, add:

```rust
    /// The explicit `beans_serve_path`, or the first `beans-serve` on `$PATH`.
    pub fn resolve_beans_serve(&self) -> anyhow::Result<PathBuf> {
        match &self.beans_serve_path {
            Some(p) => Ok(p.clone()),
            None => which::which("beans-serve").map_err(|_| {
                anyhow::anyhow!(
                    "beans-serve not found on $PATH; set beans_serve_path in dev-config.toml"
                )
            }),
        }
    }
```

Then change `validate` to check the resolved path. Replace its first line
`let meta = std::fs::metadata(&self.beans_serve_path)...` so the method reads:

```rust
    pub fn validate(&self) -> anyhow::Result<()> {
        use std::os::unix::fs::PermissionsExt;
        let path = self.resolve_beans_serve()?;
        let meta = std::fs::metadata(&path).map_err(|e| {
            anyhow::anyhow!("beans_serve_path {} unreadable: {e}", path.display())
        })?;
        if !meta.is_file() {
            anyhow::bail!("beans_serve_path {} is not a file", path.display());
        }
        if meta.permissions().mode() & 0o111 == 0 {
            anyhow::bail!("beans_serve_path {} is not executable", path.display());
        }
        Ok(())
    }
```

- [ ] **Step 5: Update existing tests for the `Option` field**

In `crates/beansd/src/config.rs`, fix the now-broken assertions/literals:

- In `parses_minimal_config` and `parses_full_config`, the assertion becomes:
  ```rust
  assert_eq!(cfg.beans_serve_path, Some(PathBuf::from("/usr/bin/beans-serve")));
  ```
  (`parses_full_config` uses the nix-store path string it already has — wrap it in `Some(PathBuf::from(...))`.)
- Replace the test `missing_beans_serve_path_errors` with:
  ```rust
  #[test]
  fn missing_beans_serve_path_is_none() {
      let toml = r#"launcher_port = 9000"#;
      let cfg: Config = toml::from_str(toml).unwrap();
      assert_eq!(cfg.beans_serve_path, None);
  }
  ```
- In every `Config { .. }` literal in `mod load_tests` (`validate_passes_for_executable`, `validate_fails_for_missing_file`, `validate_fails_for_non_executable`), wrap the path: `beans_serve_path: Some(bin)` / `Some(PathBuf::from("/no/such/binary"))` / `Some(f)`.

- [ ] **Step 6: Use the resolved path when building the spawner**

In `crates/beansd/src/run.rs`, change lines 27-29 from:

```rust
    let spawner = BeansServeSpawner {
        binary: cfg.beans_serve_path.clone(),
    };
```

to:

```rust
    let spawner = BeansServeSpawner {
        binary: cfg.resolve_beans_serve()?,
    };
```

- [ ] **Step 7: Run the config tests, expect pass**

Run: `cargo test -p beansd`
Expected: PASS (new `resolve_*` tests and all updated existing tests).

- [ ] **Step 8: Commit**

```bash
git add crates/beansd/src/config.rs crates/beansd/src/run.rs
git commit -m "crates beansd: resolve beans_serve_path from \$PATH when omitted (dotfiles-z3aj)"
```
