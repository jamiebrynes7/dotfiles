---
# dotfiles-hm5p
title: 'default_path: dev flag + repo-local dev-config.toml'
status: todo
type: task
priority: normal
created_at: 2026-05-30T18:33:00Z
updated_at: 2026-05-30T18:33:45Z
parent: dotfiles-i5zy
blocked_by:
    - dotfiles-m8nc
---

Make `Config::default_path` flavor-aware: in dev it points at the repo-local `dev-config.toml`, resolved from the crate's compile-time source dir so it's independent of the working directory. Add the checked-in dev config (port 9001, no `beans_serve_path`). Update the one call site to pass `false` for now (the real `dev` value is threaded in the binaries task).

**Files:**
- Modify: `crates/beansd/src/config.rs:24-27` (`default_path`)
- Modify: `crates/beansd/src/run.rs:14` (caller passes `false`)
- Create: `crates/beansd/dev-config.toml`
- Test: `crates/beansd/src/config.rs`

- [ ] **Step 1: Write the failing tests**

Add to `mod load_tests` in `crates/beansd/src/config.rs`:

```rust
#[test]
fn dev_default_path_points_at_repo_dev_config() {
    let p = Config::default_path(true).unwrap();
    assert!(p.ends_with("dev-config.toml"), "got {}", p.display());
}

#[test]
fn prod_default_path_points_at_xdg_config() {
    let p = Config::default_path(false).unwrap();
    assert!(p.ends_with("config.toml"));
    assert!(!p.ends_with("dev-config.toml"));
}
```

(`Path::ends_with` matches whole path components, so `dev-config.toml` does not satisfy `ends_with("config.toml")` — these two assertions are distinct.)

- [ ] **Step 2: Run them, expect failure**

Run: `cargo test -p beansd default_path`
Expected: FAILS to compile — `default_path` takes no arguments yet.

- [ ] **Step 3: Add the `dev` parameter**

In `crates/beansd/src/config.rs`, replace `default_path` with:

```rust
    /// Resolve the config path for the current flavor. Prod:
    /// `$XDG_CONFIG_HOME/beans-daemon/config.toml`. Dev: the repo-local
    /// `dev-config.toml` next to this crate's source.
    pub fn default_path(dev: bool) -> anyhow::Result<PathBuf> {
        if dev {
            return Ok(PathBuf::from(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/dev-config.toml"
            )));
        }
        let dirs = xdg::BaseDirectories::with_prefix("beans-daemon")?;
        Ok(dirs.get_config_file("config.toml"))
    }
```

- [ ] **Step 4: Update the call site to pass `false`**

In `crates/beansd/src/run.rs:14`:

```rust
    let cfg = Config::load(&Config::default_path(false)?)?;
```

- [ ] **Step 5: Create the dev config**

Create `crates/beansd/dev-config.toml`:

```toml
# Dev instance config, loaded by `beansd --dev`. Kept in-repo (not deployed by
# home-manager). beans_serve_path is intentionally omitted — beansd resolves
# `beans-serve` from $PATH, so this never goes stale against nix-store churn.
launcher_port  = 9001
lru_cap        = 8
heartbeat_secs = 15
log_level      = "debug"
```

- [ ] **Step 6: Run the tests, expect pass**

Run: `cargo test -p beansd default_path`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add crates/beansd/src/config.rs crates/beansd/src/run.rs crates/beansd/dev-config.toml
git commit -m "crates beansd: add dev config path + dev-config.toml (dotfiles-z3aj)"
```
