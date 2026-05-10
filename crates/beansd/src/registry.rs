use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Debug)]
pub struct Project {
    pub key: PathBuf,
    pub display_name: String,
    pub last_used: Instant,
    pub state: ProjectState,
}

#[derive(Debug)]
pub enum ProjectState {
    Spawning {
        since: Instant,
    },
    Healthy {
        port: u16,
        pid: u32,
        spawned_at: Instant,
    },
    Evicting {
        since: Instant,
    },
    Dead {
        reason: String,
        since: Instant,
    },
}

impl ProjectState {
    /// True when the project counts toward the LRU cap.
    /// Evicting and Dead projects don't.
    pub fn counts_toward_cap(&self) -> bool {
        matches!(
            self,
            ProjectState::Spawning { .. } | ProjectState::Healthy { .. }
        )
    }
}

#[derive(Debug, Default)]
pub struct Registry {
    by_key: HashMap<PathBuf, Project>,
}

impl Registry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, key: &Path) -> Option<&Project> {
        self.by_key.get(key)
    }

    /// Insert a fresh `Spawning` project. Errors if the key already exists.
    pub fn insert_spawning(
        &mut self,
        key: PathBuf,
        display_name: String,
        now: Instant,
    ) -> anyhow::Result<()> {
        if self.by_key.contains_key(&key) {
            anyhow::bail!("project already registered: {}", key.display());
        }
        self.by_key.insert(
            key.clone(),
            Project {
                key,
                display_name,
                last_used: now,
                state: ProjectState::Spawning { since: now },
            },
        );
        Ok(())
    }

    /// Bump the project's `last_used` to `now`. No-op if the project doesn't exist.
    pub fn bump_last_used(&mut self, key: &Path, now: Instant) {
        if let Some(p) = self.by_key.get_mut(key) {
            p.last_used = now;
        }
    }

    /// Number of projects whose state counts toward the LRU cap.
    pub fn count_active(&self) -> usize {
        self.by_key
            .values()
            .filter(|p| p.state.counts_toward_cap())
            .count()
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
    pub fn transition_state(&mut self, key: &Path, new_state: ProjectState) -> anyhow::Result<()> {
        let proj = self
            .by_key
            .get_mut(key)
            .ok_or_else(|| anyhow::anyhow!("unknown project: {}", key.display()))?;
        proj.state = new_state;
        Ok(())
    }

    /// Drop a project from the registry. Returns whether it existed.
    pub fn remove(&mut self, key: &Path) -> bool {
        self.by_key.remove(key).is_some()
    }

    /// Iterate snapshots of all projects (for /api/projects rendering).
    pub fn iter(&self) -> impl Iterator<Item = &Project> {
        self.by_key.values()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_toward_cap_for_active_states() {
        let now = Instant::now();
        assert!(ProjectState::Spawning { since: now }.counts_toward_cap());
        assert!(
            ProjectState::Healthy {
                port: 1,
                pid: 2,
                spawned_at: now
            }
            .counts_toward_cap()
        );
        assert!(!ProjectState::Evicting { since: now }.counts_toward_cap());
        assert!(
            !ProjectState::Dead {
                reason: "x".into(),
                since: now
            }
            .counts_toward_cap()
        );
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
        r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), now)
            .unwrap();
        let proj = r.get(Path::new("/tmp/p")).unwrap();
        assert!(matches!(proj.state, ProjectState::Spawning { .. }));
        assert_eq!(proj.display_name, "p");
    }

    #[test]
    fn duplicate_insert_errors() {
        let mut r = Registry::new();
        let now = Instant::now();
        r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), now)
            .unwrap();
        assert!(
            r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), now)
                .is_err()
        );
    }

    #[test]
    fn bump_updates_last_used() {
        let mut r = Registry::new();
        let t0 = Instant::now();
        r.insert_spawning(PathBuf::from("/tmp/p"), "p".into(), t0)
            .unwrap();
        let t1 = t0 + Duration::from_secs(10);
        r.bump_last_used(Path::new("/tmp/p"), t1);
        assert_eq!(r.get(Path::new("/tmp/p")).unwrap().last_used, t1);
    }

    #[test]
    fn bump_missing_is_noop() {
        let mut r = Registry::new();
        r.bump_last_used(Path::new("/tmp/missing"), Instant::now());
        assert!(r.get(Path::new("/tmp/missing")).is_none());
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
        r.transition_state(Path::new("/tmp/b"), ProjectState::Evicting { since: now })
            .unwrap();
        r.insert_spawning("/tmp/c".into(), "c".into(), now).unwrap();
        r.transition_state(
            Path::new("/tmp/c"),
            ProjectState::Dead {
                reason: "x".into(),
                since: now,
            },
        )
        .unwrap();
        assert_eq!(r.count_active(), 1);
    }

    #[test]
    fn find_lru_picks_oldest_active() {
        let mut r = Registry::new();
        let t0 = Instant::now();
        r.insert_spawning("/tmp/a".into(), "a".into(), t0).unwrap();
        r.insert_spawning("/tmp/b".into(), "b".into(), t0 + Duration::from_secs(1))
            .unwrap();
        r.insert_spawning("/tmp/c".into(), "c".into(), t0 + Duration::from_secs(2))
            .unwrap();
        assert_eq!(r.find_lru_for_eviction(), Some("/tmp/a".into()));
    }

    #[test]
    fn find_lru_skips_evicting() {
        let mut r = Registry::new();
        let t0 = Instant::now();
        r.insert_spawning("/tmp/a".into(), "a".into(), t0).unwrap();
        r.insert_spawning("/tmp/b".into(), "b".into(), t0 + Duration::from_secs(1))
            .unwrap();
        r.transition_state(Path::new("/tmp/a"), ProjectState::Evicting { since: t0 })
            .unwrap();
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
        let err = r.transition_state(
            Path::new("/tmp/missing"),
            ProjectState::Dead {
                reason: "x".into(),
                since: now,
            },
        );
        assert!(err.is_err());
    }
}
