---
# dotfiles-4f2a
title: Extract beansd-rpc skeleton (wire + socket)
status: todo
type: task
priority: normal
created_at: 2026-05-10T14:55:47Z
updated_at: 2026-05-10T14:59:40Z
parent: dotfiles-qwfb
blocked_by:
    - dotfiles-7zn7
---

**Files:**
- Create: `crates/beansd-rpc/Cargo.toml`
- Create: `crates/beansd-rpc/src/lib.rs`
- Move: `crates/beansd/src/protocol.rs` → `crates/beansd-rpc/src/wire.rs` (rename `Request` → `WireRequest`, `Response` → `WireResponse`; visibility stays `pub` for now — tightened in Task 5)
- Create: `crates/beansd-rpc/src/socket.rs` (lift `default_socket_path` and `bind_uds` from `crates/beansd/src/control.rs`)
- Modify: `crates/beansd/src/control.rs` (delete the moved fns + their tests)
- Modify: `crates/beansd/src/main.rs` (drop `mod protocol;`)
- Modify: `crates/beansd/src/cli_client.rs` (import wire types from `beansd_rpc`)
- Modify: `crates/beansd/src/run.rs` (import socket helpers from `beansd_rpc`)
- Modify: `crates/beansd/Cargo.toml` (add `beansd-rpc = { path = "../beansd-rpc" }`)

Pure carve-out. No new behavior. After this task the 4 wire tests + 3 socket tests run from `beansd-rpc`; daemon test count drops by 7; total is unchanged.

- [ ] **Step 1: Create the new crate's `Cargo.toml`**

`crates/beansd-rpc/Cargo.toml`:

```toml
[package]
name = "beansd-rpc"
version.workspace = true
edition.workspace = true

[dependencies]
anyhow.workspace = true
serde.workspace = true
serde_json.workspace = true
tokio.workspace = true
tracing.workspace = true

[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 2: Move `protocol.rs` to `wire.rs` and rename types**

```bash
mkdir -p crates/beansd-rpc/src
git mv crates/beansd/src/protocol.rs crates/beansd-rpc/src/wire.rs
```

Then replace `crates/beansd-rpc/src/wire.rs` contents with:

```rust
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
#[serde(tag = "op", content = "args", rename_all = "snake_case")]
pub enum WireRequest {
    Cd { cwd: PathBuf },
    Ls {},
    Start { key: PathBuf },
    Stop { key: PathBuf },
    Status {},
    Heartbeat { key: PathBuf },
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum WireResponse {
    Ok { ok: bool, data: serde_json::Value },
    Error { ok: bool, error: String },
}

impl WireResponse {
    pub fn ok(data: serde_json::Value) -> Self {
        WireResponse::Ok { ok: true, data }
    }

    pub fn err(msg: impl Into<String>) -> Self {
        WireResponse::Error { ok: false, error: msg.into() }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn round_trips_cd_request() {
        let r = WireRequest::Cd { cwd: PathBuf::from("/abs/path") };
        let s = serde_json::to_string(&r).unwrap();
        assert_eq!(s, r#"{"op":"cd","args":{"cwd":"/abs/path"}}"#);
        let back: WireRequest = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn round_trips_ls_request_with_empty_args() {
        let r = WireRequest::Ls {};
        let s = serde_json::to_string(&r).unwrap();
        assert_eq!(s, r#"{"op":"ls","args":{}}"#);
        let back: WireRequest = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn ok_response_serialises_with_ok_true() {
        let s = serde_json::to_string(&WireResponse::ok(json!({"x": 1}))).unwrap();
        assert!(s.contains(r#""ok":true"#));
        assert!(s.contains(r#""x":1"#));
    }

    #[test]
    fn err_response_serialises_with_ok_false() {
        let s = serde_json::to_string(&WireResponse::err("boom")).unwrap();
        assert!(s.contains(r#""ok":false"#));
        assert!(s.contains(r#""error":"boom""#));
    }
}
```

- [ ] **Step 3: Create `crates/beansd-rpc/src/socket.rs`**

```rust
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
```

- [ ] **Step 4: Create `crates/beansd-rpc/src/lib.rs`**

```rust
mod socket;
mod wire;

pub use socket::{bind_uds, default_socket_path};
pub use wire::{WireRequest, WireResponse};
```

- [ ] **Step 5: Strip moved code from `crates/beansd/src/control.rs`**

In `crates/beansd/src/control.rs`, delete:

- The `default_socket_path()` and `bind_uds()` function definitions.
- The imports they require: `use anyhow::Context;`, `use std::os::unix::fs::PermissionsExt;`, `use tokio::net::UnixListener;` (replace `UnixListener` import with `use tokio::net::UnixStream;` if needed for `serve_uds`).
- The `#[cfg(test)] mod tests { ... }` block at the bottom that contains the three `bind_uds_*` tests.

Keep: `Daemon` struct, all `handle_*` methods, `serve_uds`, `handle_connection`, `mod cd_tests`, `mod handler_tests`.

Add at the top of `control.rs`:

```rust
use beansd_rpc::{WireRequest as Request, WireResponse as Response};
```

Remove (if present): `use crate::protocol::{Request, Response};`. The rename-on-import preserves all uses of `Request` / `Response` inside `control.rs`, minimising diff.

- [ ] **Step 6: Drop `mod protocol;` from `crates/beansd/src/main.rs`**

In `crates/beansd/src/main.rs`, remove the line `mod protocol;`. All other `mod` declarations stay.

- [ ] **Step 7: Update `crates/beansd/src/cli_client.rs` imports**

Replace the line `use crate::protocol::{Request, Response};` with:

```rust
use beansd_rpc::{WireRequest as Request, WireResponse as Response};
```

Rest of file unchanged.

- [ ] **Step 8: Update `crates/beansd/src/run.rs` imports**

Replace the line `use crate::control::{Daemon, bind_uds, default_socket_path};` with:

```rust
use crate::control::Daemon;
use beansd_rpc::{bind_uds, default_socket_path};
```

Rest of file unchanged.

- [ ] **Step 9: Add `beansd-rpc` dep in `crates/beansd/Cargo.toml`**

In the `[dependencies]` section, add (kept alphabetical):

```toml
beansd-rpc = { path = "../beansd-rpc" }
```

- [ ] **Step 10: Run the full workspace test suite**

```bash
nix develop --command cargo test --manifest-path Cargo.toml --workspace
```

Expected: 61 tests still pass. The 7 moved tests now report under `beansd-rpc::wire::tests` and `beansd-rpc::socket::tests` instead of `beansd::protocol::tests` and `beansd::control::tests`. Net unchanged.

- [ ] **Step 11: Commit**

```bash
git add Cargo.lock crates/
git commit -m "crates/beansd-rpc: extract wire types and socket helpers"
```
