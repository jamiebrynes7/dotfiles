---
# dotfiles-xdxz
title: '`Registry` with insert + bump_last_used'
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:34:36Z
updated_at: 2026-05-09T13:50:40Z
parent: dotfiles-yejq
---

**Files:**
- Modify: `packages/beans-daemon/src/registry.rs`

- [x] **Step 1: Write the failing test**

Append to `packages/beans-daemon/src/registry.rs`:
```rust
use std::collections::HashMap;

#[derive(Debug, Default)]
pub struct Registry {
    by_key: HashMap<PathBuf, Project>,
}

impl Registry {
    pub fn new() -> Self { Self::default() }

    pub fn get(&self, key: &PathBuf) -> Option<&Project> {
        self.by_key.get(key)
    }

    /// Insert a fresh `Spawning` project. Errors if the key already exists.
    pub fn insert_spawning(&mut self, key: PathBuf, display_name: String, now: Instant) -> anyhow::Result<()> {
        if self.by_key.contains_key(&key) {
            anyhow::bail!("project already registered: {}", key.display());
        }
        self.by_key.insert(key.clone(), Project {
            key,
            display_name,
            last_used: now,
            state:     ProjectState::Spawning { since: now },
        });
        Ok(())
    }

    /// Bump the project's `last_used` to `now`. No-op if the project doesn't exist.
    pub fn bump_last_used(&mut self, key: &PathBuf, now: Instant) {
        if let Some(p) = self.by_key.get_mut(key) {
            p.last_used = now;
        }
    }
}

#[cfg(test)]
mod registry_tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn insert_spawning_adds_to_registry() {
        let mut r = Registry::new();
        let now = Instant::now();
        r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), now).unwrap();
        let proj = r.get(&PathBuf::from("/tmp/p")).unwrap();
        assert!(matches!(proj.state, ProjectState::Spawning { .. }));
        assert_eq!(proj.display_name, "p");
    }

    #[test]
    fn duplicate_insert_errors() {
        let mut r = Registry::new();
        let now = Instant::now();
        r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), now).unwrap();
        assert!(r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), now).is_err());
    }

    #[test]
    fn bump_updates_last_used() {
        let mut r = Registry::new();
        let t0 = Instant::now();
        r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), t0).unwrap();
        let t1 = t0 + Duration::from_secs(10);
        r.bump_last_used(&PathBuf::from("/tmp/p"), t1);
        assert_eq!(r.get(&PathBuf::from("/tmp/p")).unwrap().last_used, t1);
    }

    #[test]
    fn bump_missing_is_noop() {
        let mut r = Registry::new();
        r.bump_last_used(&PathBuf::from("/tmp/missing"), Instant::now());
        assert!(r.get(&PathBuf::from("/tmp/missing")).is_none());
    }
}
```

- [x] **Step 2: Run tests**

Run: `cargo test registry::`
Expected: all 5 tests pass (the existing `tests::counts_toward_cap_for_active_states` plus the new 4).

- [x] **Step 3: Commit**

```bash
git add packages/beans-daemon/src/registry.rs
git commit -m "packages/beans-daemon: Registry insert + bump_last_used"
```

## Summary of Changes

- Added `Registry` struct (HashMap-backed by `PathBuf` key) with `new`, `get`, `insert_spawning`, `bump_last_used`.
- `insert_spawning` errors on duplicate keys; `bump_last_used` is a no-op for missing keys (per spec).
- Took the `&Path` flavour for `get` and `bump_last_used` parameters rather than `&PathBuf` — strictly more general, satisfies `clippy::ptr_arg`, and tests still pass via deref coercion.
- 4 new tests under `registry_tests`; combined `cargo test registry::` runs 5 passing tests.
