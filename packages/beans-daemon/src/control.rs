use anyhow::Context;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use tokio::net::UnixListener;

pub fn default_socket_path() -> anyhow::Result<PathBuf> {
    if cfg!(target_os = "macos") {
        let home = std::env::var("HOME").context("HOME unset")?;
        Ok(PathBuf::from(home).join("Library/Caches/beans-daemon/sock"))
    } else {
        let xdg = std::env::var("XDG_RUNTIME_DIR").context("XDG_RUNTIME_DIR unset")?;
        Ok(PathBuf::from(xdg).join("beans-daemon.sock"))
    }
}

pub fn bind_uds(path: &Path) -> anyhow::Result<UnixListener> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    if path.exists() {
        if std::os::unix::net::UnixStream::connect(path).is_ok() {
            anyhow::bail!("socket {} already in use by a live daemon", path.display());
        }
        let _ = std::fs::remove_file(path);
    }
    let listener =
        UnixListener::bind(path).with_context(|| format!("binding {}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(listener)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn bind_uds_creates_socket_with_0600() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("sock");
        let _l = bind_uds(&path).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[tokio::test]
    async fn bind_uds_unlinks_stale_socket() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("sock");
        std::fs::write(&path, b"").unwrap();
        let _l = bind_uds(&path).unwrap();
    }

    #[tokio::test]
    async fn bind_uds_refuses_to_replace_live_socket() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("sock");
        let _l1 = bind_uds(&path).unwrap();
        let res = bind_uds(&path);
        assert!(res.is_err());
        assert!(res.err().unwrap().to_string().contains("already in use"));
    }
}
