---
# dotfiles-rpa4
title: UDS server bind (with stale-socket cleanup + 0600 perms)
status: todo
type: task
created_at: 2026-05-03T14:38:16Z
updated_at: 2026-05-03T14:38:16Z
parent: dotfiles-2ecf
---

**Files:**
- Create: `packages/beans-daemon/src/control.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod control;`)

Per spec §2 + failure modes: 0600 perms, unlink stale socket file before bind, second instance fails on bind.

- [ ] **Step 1: Write the failing test**

Create `packages/beans-daemon/src/control.rs`:
```rust
use anyhow::Context;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use tokio::net::UnixListener;

/// Resolve the daemon's UDS path:
///   Linux: \$XDG_RUNTIME_DIR/beans-daemon.sock
///   macOS: \$HOME/Library/Caches/beans-daemon/sock
pub fn default_socket_path() -> anyhow::Result<std::path::PathBuf> {
    if cfg!(target_os = "macos") {
        let home = std::env::var("HOME").context("HOME unset")?;
        Ok(std::path::PathBuf::from(home).join("Library/Caches/beans-daemon/sock"))
    } else {
        let xdg = std::env::var("XDG_RUNTIME_DIR").context("XDG_RUNTIME_DIR unset")?;
        Ok(std::path::PathBuf::from(xdg).join("beans-daemon.sock"))
    }
}

/// Bind a Unix listener at `path`. Unlinks any stale socket file first.
/// Sets permissions to 0600. Errors if a live daemon is already bound.
pub fn bind_uds(path: &Path) -> anyhow::Result<UnixListener> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    if path.exists() {
        // Try connecting; if it succeeds, another daemon is alive.
        if std::os::unix::net::UnixStream::connect(path).is_ok() {
            anyhow::bail!("socket {} already in use by a live daemon", path.display());
        }
        let _ = std::fs::remove_file(path);
    }
    let listener = UnixListener::bind(path)
        .with_context(|| format!("binding {}", path.display()))?;
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
        std::fs::write(&path, b"").unwrap();  // stale file (not a socket)
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test control::`
Expected: FAIL — module not declared.

- [ ] **Step 3: Wire into main.rs**

Add `mod control;`.

- [ ] **Step 4: Run tests**

Run: `cargo test control::`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/control.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: UDS bind with stale-socket cleanup"
```
