use crate::registry::{ProjectState, Registry};
use std::path::PathBuf;

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
