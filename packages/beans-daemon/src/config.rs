use serde::Deserialize;
use std::path::{Path, PathBuf};

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

impl Config {
    /// Resolve the canonical config path for the current user:
    /// `$XDG_CONFIG_HOME/beans-daemon/config.toml`, falling back to
    /// `$HOME/.config/beans-daemon/config.toml`.
    pub fn default_path() -> anyhow::Result<PathBuf> {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
            .ok_or_else(|| anyhow::anyhow!("neither XDG_CONFIG_HOME nor HOME is set"))?;
        Ok(base.join("beans-daemon").join("config.toml"))
    }

    /// Load and parse the config file at `path`.
    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let raw = std::fs::read_to_string(path)
            .map_err(|e| anyhow::anyhow!("reading {}: {e}", path.display()))?;
        toml::from_str(&raw).map_err(|e| anyhow::anyhow!("parsing {}: {e}", path.display()))
    }
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

#[cfg(test)]
mod load_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn loads_from_path() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("config.toml");
        std::fs::write(&path, r#"beans_serve_path = "/usr/bin/beans-serve""#).unwrap();
        let cfg = Config::load(&path).unwrap();
        assert_eq!(cfg.launcher_port, 9000);
    }

    #[test]
    fn missing_file_returns_error_with_path() {
        let err = Config::load(Path::new("/no/such/file.toml")).unwrap_err();
        assert!(err.to_string().contains("/no/such/file.toml"));
    }

    #[test]
    fn default_path_uses_xdg_when_set() {
        let prev = std::env::var("XDG_CONFIG_HOME").ok();
        std::env::set_var("XDG_CONFIG_HOME", "/tmp/xdg");
        let p = Config::default_path().unwrap();
        assert_eq!(p, PathBuf::from("/tmp/xdg/beans-daemon/config.toml"));
        match prev {
            Some(v) => std::env::set_var("XDG_CONFIG_HOME", v),
            None => std::env::remove_var("XDG_CONFIG_HOME"),
        }
    }
}
