use crate::registry::{ProjectState, Registry};
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub(in crate::web) struct ProjectView {
    pub(in crate::web) key: PathBuf,
    pub(in crate::web) display_name: String,
    pub(in crate::web) state: &'static str,
    pub(in crate::web) port: Option<u16>,
}

pub(in crate::web) fn project_views(reg: &Registry) -> Vec<ProjectView> {
    reg.iter()
        .map(|p| {
            let (state, port) = match &p.state {
                ProjectState::Spawning { .. } => ("spawning", None),
                ProjectState::Healthy { port, .. } => ("healthy", Some(*port)),
                ProjectState::Evicting { .. } => ("evicting", None),
                ProjectState::Dead { .. } => ("dead", None),
            };
            ProjectView {
                key: p.key.clone(),
                display_name: p.display_name.clone(),
                state,
                port,
            }
        })
        .collect()
}

/// Resolves the active project for a given query key. A project is only
/// considered active if it is registered under `key` *and* currently has a
/// port — i.e. it is healthy enough to be embedded in the iframe.
pub(in crate::web) fn resolve_active(
    projects: &[ProjectView],
    key: Option<&Path>,
) -> Option<ProjectView> {
    let key = key?;
    projects
        .iter()
        .find(|p| p.key == key && p.port.is_some())
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn view(key: &str, port: Option<u16>) -> ProjectView {
        ProjectView {
            key: PathBuf::from(key),
            display_name: key.into(),
            state: if port.is_some() { "healthy" } else { "dead" },
            port,
        }
    }

    #[test]
    fn resolve_active_returns_match_only_when_port_present() {
        let projects = vec![view("/a", Some(4242)), view("/b", None)];
        let a = PathBuf::from("/a");
        let b = PathBuf::from("/b");
        let missing = PathBuf::from("/c");

        assert!(resolve_active(&projects, Some(&a)).is_some());
        assert!(resolve_active(&projects, Some(&b)).is_none(), "no port -> None");
        assert!(resolve_active(&projects, Some(&missing)).is_none());
        assert!(resolve_active(&projects, None).is_none());
    }
}
