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
