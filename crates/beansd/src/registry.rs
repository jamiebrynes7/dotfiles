use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::Instant;

use crate::spawner::ChildHandle;

pub struct Project {
    pub key: PathBuf,
    pub display_name: String,
    pub last_used: Instant,
    pub state: ProjectState,
    pub since: Instant,
}

impl Project {
    pub fn new(key: PathBuf, display_name: String, state: ProjectState) -> Self {
        let now = Instant::now();
        Self {
            key,
            display_name,
            state,
            last_used: now,
            since: now,
        }
    }

    // Sets the current state of the project and returns the prior state.
    pub fn set_state(&mut self, mut state: ProjectState) -> ProjectState {
        std::mem::swap(&mut self.state, &mut state);
        self.since = Instant::now();

        state
    }
}

pub enum ProjectState {
    Spawning,
    Healthy {
        port: u16,
        child: Box<dyn ChildHandle>,
    },
    Evicting,
    Dead {
        reason: String,
    },
}

#[derive(Default)]
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

    /// Insert a fresh project. Errors if the key already exists.
    pub fn insert(&mut self, project: Project) -> anyhow::Result<()> {
        let key = project.key.clone();
        if self.by_key.contains_key(&key) {
            anyhow::bail!("project already registered: {}", key.display());
        }
        self.by_key.insert(key, project);
        Ok(())
    }

    /// Bump the project's `last_used` to `now`. No-op if the project doesn't exist.
    pub fn bump_last_used(&mut self, key: &Path, now: Instant) {
        if let Some(p) = self.by_key.get_mut(key) {
            p.last_used = now;
        }
    }

    /// Replace a project's state. Errors if the key isn't registered.
    pub fn transition_state(
        &mut self,
        key: &Path,
        new_state: ProjectState,
    ) -> anyhow::Result<ProjectState> {
        let proj = self
            .by_key
            .get_mut(key)
            .ok_or_else(|| anyhow::anyhow!("unknown project: {}", key.display()))?;

        Ok(proj.set_state(new_state))
    }

    /// Iterate snapshots of all projects (for /api/projects rendering).
    pub fn iter(&self) -> impl Iterator<Item = &Project> {
        self.by_key.values()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn insert_adds_to_registry() {
        let mut r = Registry::new();

        let res = r.insert(Project::new(
            PathBuf::from("/tmp/p"),
            "p".into(),
            ProjectState::Spawning,
        ));

        assert!(res.is_ok(), "Failed to insert project");

        let fetched = r.get(Path::new("/tmp/p"));
        assert!(fetched.is_some());
    }

    #[test]
    fn duplicate_insert_errors() {
        let mut r = Registry::new();
        let res = r.insert(Project::new(
            PathBuf::from("/tmp/p"),
            "p".into(),
            ProjectState::Spawning,
        ));

        assert!(res.is_ok(), "Failed to insert project");

        let res = r.insert(Project::new(
            PathBuf::from("/tmp/p"),
            "p".into(),
            ProjectState::Spawning,
        ));

        assert!(res.is_err());
    }

    #[test]
    fn bump_updates_last_used() {
        let mut r = Registry::new();

        let t0 = Instant::now();

        test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                PathBuf::from("/tmp/p"),
                "p".into(),
                ProjectState::Spawning,
            )],
        );

        let t1 = t0 + Duration::from_secs(10);

        assert_ne!(r.get(Path::new("/tmp/p")).unwrap().last_used, t1);
        r.bump_last_used(Path::new("/tmp/p"), t1);
        assert_eq!(r.get(Path::new("/tmp/p")).unwrap().last_used, t1);
    }

    #[test]
    fn bump_missing_is_noop() {
        let mut r = Registry::new();
        r.bump_last_used(Path::new("/tmp/missing"), Instant::now());
        assert!(r.get(Path::new("/tmp/missing")).is_none());
    }

    #[test]
    fn transition_state_unknown_key_errors() {
        let mut r = Registry::new();
        let err = r.transition_state(
            Path::new("/tmp/missing"),
            ProjectState::Dead { reason: "x".into() },
        );
        assert!(err.is_err());
    }
}

#[cfg(test)]
pub mod test_utils {
    use crate::registry::{Project, Registry};

    pub fn seed_registry(registry: &mut Registry, projects: Vec<Project>) {
        for p in projects {
            registry.by_key.insert(p.key.clone(), p);
        }
    }
}
