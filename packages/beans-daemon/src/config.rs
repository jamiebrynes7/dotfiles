use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    #[serde(default = "defaults::launcher_port")]
    pub launcher_port: u16,
    #[serde(default = "defaults::lru_cap")]
    pub lru_cap: usize,
    #[serde(default = "defaults::heartbeat_secs")]
    pub heartbeat_secs: u64,
    #[serde(default = "defaults::log_level")]
    pub log_level: String,
    /// Absolute path to the `beans-serve` binary.
    /// Required — rendered by the home-manager module.
    pub beans_serve_path: PathBuf,
}

mod defaults {
    pub fn launcher_port() -> u16 {
        9000
    }
    pub fn lru_cap() -> usize {
        8
    }
    pub fn heartbeat_secs() -> u64 {
        15
    }
    pub fn log_level() -> String {
        "info".into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_config() {
        let toml = r#"beans_serve_path = "/usr/bin/beans-serve""#;
        let cfg: Config = toml::from_str(toml).unwrap();
        assert_eq!(cfg.launcher_port, 9000);
        assert_eq!(cfg.lru_cap, 8);
        assert_eq!(cfg.heartbeat_secs, 15);
        assert_eq!(cfg.log_level, "info");
        assert_eq!(cfg.beans_serve_path, PathBuf::from("/usr/bin/beans-serve"));
    }

    #[test]
    fn parses_full_config() {
        let toml = r#"
launcher_port    = 9100
lru_cap          = 4
heartbeat_secs   = 30
log_level        = "debug"
beans_serve_path = "/nix/store/x/bin/beans-serve"
"#;
        let cfg: Config = toml::from_str(toml).unwrap();
        assert_eq!(cfg.launcher_port, 9100);
        assert_eq!(cfg.lru_cap, 4);
    }

    #[test]
    fn missing_beans_serve_path_errors() {
        let toml = r#"launcher_port = 9000"#;
        let err = toml::from_str::<Config>(toml).unwrap_err();
        assert!(err.to_string().contains("beans_serve_path"));
    }

    #[test]
    fn unknown_field_errors() {
        let toml = r#"
beans_serve_path = "/usr/bin/beans-serve"
launcher_prot    = 9000
"#;
        assert!(toml::from_str::<Config>(toml).is_err());
    }
}
