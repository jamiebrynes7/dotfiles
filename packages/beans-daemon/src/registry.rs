use std::path::PathBuf;
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
