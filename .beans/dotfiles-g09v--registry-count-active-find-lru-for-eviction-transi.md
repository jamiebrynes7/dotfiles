---
# dotfiles-g09v
title: '`Registry`: count_active, find_lru_for_eviction, transition_state'
status: todo
type: task
created_at: 2026-05-03T14:34:36Z
updated_at: 2026-05-03T14:34:36Z
parent: dotfiles-yejq
---

**Files:**
- Modify: `packages/beans-daemon/src/registry.rs`

- [ ] **Step 1: Write the failing test**

Append to `packages/beans-daemon/src/registry.rs`:
```rust
impl Registry {
    /// Number of projects whose state counts toward the LRU cap.
    pub fn count_active(&self) -> usize {
        self.by_key.values().filter(|p| p.state.counts_toward_cap()).count()
    }

    /// Find the project (by key) with the oldest `last_used` among those
    /// that count toward the cap. Used to pick an eviction candidate.
    /// Returns `None` if no candidates exist.
    pub fn find_lru_for_eviction(&self) -> Option<PathBuf> {
        self.by_key
            .values()
            .filter(|p| p.state.counts_toward_cap())
            .min_by_key(|p| p.last_used)
            .map(|p| p.key.clone())
    }

    /// Replace a project's state. Errors if the key isn't registered.
    pub fn transition_state(&mut self, key: &PathBuf, new_state: ProjectState) -> anyhow::Result<()> {
        let proj = self.by_key.get_mut(key)
            .ok_or_else(|| anyhow::anyhow!("unknown project: {}", key.display()))?;
        proj.state = new_state;
        Ok(())
    }

    /// Drop a project from the registry. Returns whether it existed.
    pub fn remove(&mut self, key: &PathBuf) -> bool {
        self.by_key.remove(key).is_some()
    }

    /// Iterate snapshots of all projects (for /api/projects rendering).
    pub fn iter(&self) -> impl Iterator<Item = &Project> {
        self.by_key.values()
    }
}

#[cfg(test)]
mod cap_tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn count_active_excludes_evicting_and_dead() {
        let mut r = Registry::new();
        let now = Instant::now();
        r.insert_spawning("/tmp/a".into(), "a".into(), now).unwrap();
        r.insert_spawning("/tmp/b".into(), "b".into(), now).unwrap();
        r.transition_state(&"/tmp/b".into(), ProjectState::Evicting { since: now }).unwrap();
        r.insert_spawning("/tmp/c".into(), "c".into(), now).unwrap();
        r.transition_state(&"/tmp/c".into(), ProjectState::Dead { reason: "x".into(), since: now }).unwrap();
        assert_eq!(r.count_active(), 1);
    }

    #[test]
    fn find_lru_picks_oldest_active() {
        let mut r = Registry::new();
        let t0 = Instant::now();
        r.insert_spawning("/tmp/a".into(), "a".into(), t0).unwrap();
        r.insert_spawning("/tmp/b".into(), "b".into(), t0 + Duration::from_secs(1)).unwrap();
        r.insert_spawning("/tmp/c".into(), "c".into(), t0 + Duration::from_secs(2)).unwrap();
        assert_eq!(r.find_lru_for_eviction(), Some("/tmp/a".into()));
    }

    #[test]
    fn find_lru_skips_evicting() {
        let mut r = Registry::new();
        let t0 = Instant::now();
        r.insert_spawning("/tmp/a".into(), "a".into(), t0).unwrap();
        r.insert_spawning("/tmp/b".into(), "b".into(), t0 + Duration::from_secs(1)).unwrap();
        r.transition_state(&"/tmp/a".into(), ProjectState::Evicting { since: t0 }).unwrap();
        assert_eq!(r.find_lru_for_eviction(), Some("/tmp/b".into()));
    }

    #[test]
    fn find_lru_returns_none_when_empty() {
        assert!(Registry::new().find_lru_for_eviction().is_none());
    }

    #[test]
    fn transition_state_unknown_key_errors() {
        let mut r = Registry::new();
        let now = Instant::now();
        let err = r.transition_state(&"/tmp/missing".into(), ProjectState::Dead { reason: "x".into(), since: now });
        assert!(err.is_err());
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cargo test registry::`
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add packages/beans-daemon/src/registry.rs
git commit -m "packages/beans-daemon: Registry count_active + find_lru_for_eviction"
```
