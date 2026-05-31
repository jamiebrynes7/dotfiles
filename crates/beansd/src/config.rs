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
    /// Resolve the config path for the current flavor. Prod:
    /// `$XDG_CONFIG_HOME/beans-daemon/config.toml`. Dev: the repo-local
    /// `dev-config.toml` next to this crate's source.
    pub fn default_path(dev: bool) -> anyhow::Result<PathBuf> {
        if dev {
            return Ok(PathBuf::from(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/dev-config.toml"
            )));
        }
        let dirs = xdg::BaseDirectories::with_prefix("beans-daemon")?;
        Ok(dirs.get_config_file("config.toml"))
    }

    /// Load and parse the config file at `path`.
    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let raw = std::fs::read_to_string(path)
            .map_err(|e| anyhow::anyhow!("reading {}: {e}", path.display()))?;
        toml::from_str(&raw).map_err(|e| anyhow::anyhow!("parsing {}: {e}", path.display()))
    }

    /// Sanity-check the loaded config. Currently: ensure `beans_serve_path`
    /// exists and is executable.
    pub fn validate(&self) -> anyhow::Result<()> {
        use std::os::unix::fs::PermissionsExt;
        let meta = std::fs::metadata(&self.beans_serve_path).map_err(|e| {
            anyhow::anyhow!(
                "beans_serve_path {} unreadable: {e}",
                self.beans_serve_path.display()
            )
        })?;
        if !meta.is_file() {
            anyhow::bail!(
                "beans_serve_path {} is not a file",
                self.beans_serve_path.display()
            );
        }
        if meta.permissions().mode() & 0o111 == 0 {
            anyhow::bail!(
                "beans_serve_path {} is not executable",
                self.beans_serve_path.display()
            );
        }
        Ok(())
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
    fn dev_default_path_points_at_repo_dev_config() {
        let p = Config::default_path(true).unwrap();
        assert!(p.ends_with("dev-config.toml"), "got {}", p.display());
    }

    #[test]
    fn prod_default_path_points_at_xdg_config() {
        let p = Config::default_path(false).unwrap();
        assert!(p.ends_with("config.toml"));
        assert!(!p.ends_with("dev-config.toml"));
    }

    #[test]
    fn validate_passes_for_executable() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempdir().unwrap();
        let bin = dir.path().join("fake-beans-serve");
        std::fs::write(&bin, "#!/bin/sh\nexit 0\n").unwrap();
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        let cfg = Config {
            launcher_port: 9000,
            lru_cap: 8,
            heartbeat_secs: 15,
            log_level: "info".into(),
            beans_serve_path: bin,
        };
        cfg.validate().unwrap();
    }

    #[test]
    fn validate_fails_for_missing_file() {
        let cfg = Config {
            launcher_port: 9000,
            lru_cap: 8,
            heartbeat_secs: 15,
            log_level: "info".into(),
            beans_serve_path: PathBuf::from("/no/such/binary"),
        };
        let err = cfg.validate().unwrap_err();
        assert!(err.to_string().contains("beans_serve_path"));
        assert!(err.to_string().contains("/no/such/binary"));
    }

    #[test]
    fn validate_fails_for_non_executable() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempdir().unwrap();
        let f = dir.path().join("not-executable");
        std::fs::write(&f, "data").unwrap();
        std::fs::set_permissions(&f, std::fs::Permissions::from_mode(0o644)).unwrap();
        let cfg = Config {
            launcher_port: 9000,
            lru_cap: 8,
            heartbeat_secs: 15,
            log_level: "info".into(),
            beans_serve_path: f,
        };
        let err = cfg.validate().unwrap_err();
        assert!(err.to_string().contains("not executable"));
    }
}
