use crate::registry::{ProjectState, Registry};
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub(in crate::web) struct ProjectView {
    /// Lookup key in links and form values: must render verbatim, never
    /// shortened to `display_path`.
    pub(in crate::web) key: PathBuf,
    pub(in crate::web) display_path: String,
    pub(in crate::web) display_name: String,
    pub(in crate::web) state: &'static str,
    pub(in crate::web) port: Option<u16>,
}

/// Canonicalized to compare against registry keys, which are themselves
/// canonical (`project_key::resolve`); without it a symlinked `$HOME` would
/// match nothing and shortening would silently never apply.
pub(in crate::web) fn home_dir() -> Option<PathBuf> {
    std::fs::canonicalize(std::env::var_os("HOME")?).ok()
}

pub(in crate::web) fn project_views(reg: &Registry, home: Option<&Path>) -> Vec<ProjectView> {
    reg.iter()
        .map(|p| {
            let (state, port) = match &p.state {
                ProjectState::Spawning => ("spawning", None),
                ProjectState::Healthy { port, .. } => ("healthy", Some(*port)),
                ProjectState::Evicting => ("evicting", None),
                ProjectState::Dead { .. } => ("dead", None),
            };
            ProjectView {
                key: p.key.clone(),
                display_path: tildify(&p.key, home),
                display_name: p.display_name.clone(),
                state,
                port,
            }
        })
        .collect()
}

fn tildify(path: &Path, home: Option<&Path>) -> String {
    let full = || path.display().to_string();
    let Some(home) = home else { return full() };
    // An empty `$HOME` has no components, so it strips as a prefix of every
    // path and would render every project as `~/<full path>`.
    if !home.is_absolute() {
        return full();
    }
    match path.strip_prefix(home) {
        Ok(rest) if rest.as_os_str().is_empty() => "~".to_string(),
        Ok(rest) => format!("~/{}", rest.display()),
        Err(_) => full(),
    }
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
            display_path: key.into(),
            display_name: key.into(),
            state: if port.is_some() { "healthy" } else { "dead" },
            port,
        }
    }

    #[test]
    fn tildify_collapses_home_prefix() {
        let home = PathBuf::from("/home/jo");
        assert_eq!(
            tildify(Path::new("/home/jo/workspace/dotfiles"), Some(&home)),
            "~/workspace/dotfiles"
        );
        assert_eq!(tildify(Path::new("/home/jo"), Some(&home)), "~");
    }

    #[test]
    fn tildify_only_collapses_a_leading_home() {
        let home = PathBuf::from("/home/jo");
        assert_eq!(
            tildify(Path::new("/srv/home/jo/p"), Some(&home)),
            "/srv/home/jo/p",
            "home appearing mid-path is not a prefix"
        );
        assert_eq!(
            tildify(Path::new("/home/jo/home/jo/p"), Some(&home)),
            "~/home/jo/p",
            "only the leading occurrence collapses, not every match"
        );
    }

    #[test]
    fn tildify_leaves_paths_outside_home_alone() {
        let home = PathBuf::from("/home/jo");
        assert_eq!(tildify(Path::new("/tmp/p"), Some(&home)), "/tmp/p");
        assert_eq!(
            tildify(Path::new("/home/jo-backup/p"), Some(&home)),
            "/home/jo-backup/p",
            "sibling dir sharing a name prefix is not under home"
        );
    }

    #[test]
    fn tildify_falls_back_without_a_usable_home() {
        assert_eq!(tildify(Path::new("/home/jo/p"), None), "/home/jo/p");
        assert_eq!(
            tildify(Path::new("/home/jo/p"), Some(Path::new(""))),
            "/home/jo/p",
            "an empty HOME must not swallow every path"
        );
    }

    #[test]
    fn resolve_active_returns_match_only_when_port_present() {
        let projects = vec![view("/a", Some(4242)), view("/b", None)];
        let a = PathBuf::from("/a");
        let b = PathBuf::from("/b");
        let missing = PathBuf::from("/c");

        assert!(resolve_active(&projects, Some(&a)).is_some());
        assert!(
            resolve_active(&projects, Some(&b)).is_none(),
            "no port -> None"
        );
        assert!(resolve_active(&projects, Some(&missing)).is_none());
        assert!(resolve_active(&projects, None).is_none());
    }
}
