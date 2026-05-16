use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ProjectState {
    Spawning,
    Healthy,
    Evicting,
    Dead,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct ProjectSummary {
    pub key: PathBuf,
    pub display_name: String,
    pub state: ProjectState,
    pub port: Option<u16>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(tag = "outcome", rename_all = "snake_case")]
pub enum CdResponse {
    NotRegistered,
    Bumped { key: PathBuf },
    Spawned { key: PathBuf },
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct LsResponse {
    pub projects: Vec<ProjectSummary>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum StartResponse {
    AlreadyActive,
    Spawning,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct StatusResponse {
    pub registry_size: usize,
    pub active: usize,
    pub lru_cap: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cd_response_not_registered_shape() {
        let s = serde_json::to_string(&CdResponse::NotRegistered).unwrap();
        assert_eq!(s, r#"{"outcome":"not_registered"}"#);
        let back: CdResponse = serde_json::from_str(&s).unwrap();
        assert_eq!(back, CdResponse::NotRegistered);
    }

    #[test]
    fn cd_response_spawned_includes_key() {
        let r = CdResponse::Spawned {
            key: PathBuf::from("/x"),
        };
        let s = serde_json::to_string(&r).unwrap();
        assert_eq!(s, r#"{"outcome":"spawned","key":"/x"}"#);
        let back: CdResponse = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn ls_response_round_trip() {
        let r = LsResponse {
            projects: vec![ProjectSummary {
                key: PathBuf::from("/p"),
                display_name: "p".into(),
                state: ProjectState::Healthy,
                port: Some(4242),
            }],
        };
        let s = serde_json::to_string(&r).unwrap();
        let back: LsResponse = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn start_response_serialises_as_string() {
        let s = serde_json::to_string(&StartResponse::AlreadyActive).unwrap();
        assert_eq!(s, r#""already_active""#);
        let back: StartResponse = serde_json::from_str(&s).unwrap();
        assert_eq!(back, StartResponse::AlreadyActive);
    }

    #[test]
    fn project_state_snake_case() {
        let s = serde_json::to_string(&ProjectState::Spawning).unwrap();
        assert_eq!(s, r#""spawning""#);
    }

    #[test]
    fn status_response_round_trip() {
        let r = StatusResponse {
            registry_size: 3,
            active: 2,
            lru_cap: 8,
        };
        let s = serde_json::to_string(&r).unwrap();
        let back: StatusResponse = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }
}
