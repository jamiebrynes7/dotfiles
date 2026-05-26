---
# dotfiles-75b5
title: Add typed messages + Handler trait + serve in beansd-rpc
status: completed
type: task
priority: normal
created_at: 2026-05-10T14:56:45Z
updated_at: 2026-05-16T07:35:37Z
parent: dotfiles-qwfb
blocked_by:
    - dotfiles-4f2a
---

**Files:**
- Create: `crates/beansd-rpc/src/types.rs`
- Create: `crates/beansd-rpc/src/server.rs`
- Modify: `crates/beansd-rpc/src/lib.rs` (re-export typed messages, `Handler`, `serve`)
- Modify: `crates/beansd-rpc/Cargo.toml` (add `async-trait`)

Pure addition. Daemon untouched. The `serve` function is exercised against a `MockHandler` test fixture; the daemon hooks it up in Task 4. After this task `cargo test --workspace` reports 71 total — 54 unchanged in beansd + 17 in beansd-rpc (4 wire + 3 socket from Task 2, plus 6 typed-message + 4 server from this task).

- [x] **Step 1: Add `async-trait` to `crates/beansd-rpc/Cargo.toml`**

In the `[dependencies]` section (kept alphabetical), add:

```toml
async-trait.workspace = true
```

- [x] **Step 2: Create `crates/beansd-rpc/src/types.rs`**

```rust
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
        let r = CdResponse::Spawned { key: PathBuf::from("/x") };
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
        let r = StatusResponse { registry_size: 3, active: 2, lru_cap: 8 };
        let s = serde_json::to_string(&r).unwrap();
        let back: StatusResponse = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }
}
```

- [x] **Step 3: Create `crates/beansd-rpc/src/server.rs`**

```rust
use crate::types::{CdResponse, LsResponse, StartResponse, StatusResponse};
use crate::wire::{WireRequest, WireResponse};
use async_trait::async_trait;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

#[async_trait]
pub trait Handler: Send + Sync + 'static {
    async fn cd(&self, cwd: PathBuf) -> anyhow::Result<CdResponse>;
    async fn ls(&self) -> anyhow::Result<LsResponse>;
    async fn start(&self, key: PathBuf) -> anyhow::Result<StartResponse>;
    async fn stop(&self, key: PathBuf) -> anyhow::Result<()>;
    async fn status(&self) -> anyhow::Result<StatusResponse>;
    async fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()>;
}

pub async fn serve<H: Handler>(
    listener: UnixListener,
    handler: Arc<H>,
) -> anyhow::Result<()> {
    loop {
        let (sock, _addr) = listener.accept().await?;
        let h = handler.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_connection(sock, h).await {
                tracing::warn!(error = ?e, "UDS connection ended with error");
            }
        });
    }
}

async fn handle_connection<H: Handler>(
    sock: UnixStream,
    handler: Arc<H>,
) -> anyhow::Result<()> {
    let (rd, mut wr) = sock.into_split();
    let mut lines = BufReader::new(rd).lines();
    while let Some(line) = lines.next_line().await? {
        let req: WireRequest = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let resp = WireResponse::err(format!("bad request: {e}"));
                let mut buf = serde_json::to_vec(&resp)?;
                buf.push(b'\n');
                let _ = wr.write_all(&buf).await;
                continue;
            }
        };
        let resp = dispatch(handler.as_ref(), req).await;
        let mut buf = serde_json::to_vec(&resp)?;
        buf.push(b'\n');
        // Best-effort: client may have closed the read half (fire-and-forget cd).
        let _ = wr.write_all(&buf).await;
    }
    Ok(())
}

async fn dispatch<H: Handler>(handler: &H, req: WireRequest) -> WireResponse {
    let result: anyhow::Result<serde_json::Value> = match req {
        WireRequest::Cd { cwd } => handler.cd(cwd).await.and_then(to_value),
        WireRequest::Ls {} => handler.ls().await.and_then(to_value),
        WireRequest::Start { key } => handler.start(key).await.and_then(to_value),
        WireRequest::Stop { key } => handler.stop(key).await.and_then(to_value),
        WireRequest::Status {} => handler.status().await.and_then(to_value),
        WireRequest::Heartbeat { key } => handler.heartbeat(key).await.and_then(to_value),
    };
    match result {
        Ok(data) => WireResponse::ok(data),
        Err(e) => WireResponse::err(format!("{e:#}")),
    }
}

fn to_value<T: serde::Serialize>(t: T) -> anyhow::Result<serde_json::Value> {
    serde_json::to_value(t).map_err(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::socket::bind_uds;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tempfile::tempdir;
    use tokio::net::UnixStream as ClientStream;

    /// Mock handler that records call counts and lets tests force a failure on the next op.
    struct MockHandler {
        cd_calls: AtomicUsize,
        ls_calls: AtomicUsize,
        fail_next: AtomicUsize,
    }

    impl MockHandler {
        fn new() -> Self {
            Self {
                cd_calls: AtomicUsize::new(0),
                ls_calls: AtomicUsize::new(0),
                fail_next: AtomicUsize::new(0),
            }
        }
        fn check_fail(&self) -> Option<anyhow::Error> {
            let prev = self.fail_next.load(Ordering::SeqCst);
            if prev > 0 {
                self.fail_next.store(prev - 1, Ordering::SeqCst);
                Some(anyhow::anyhow!("mock failure"))
            } else {
                None
            }
        }
    }

    #[async_trait]
    impl Handler for MockHandler {
        async fn cd(&self, _cwd: PathBuf) -> anyhow::Result<CdResponse> {
            self.cd_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(e) = self.check_fail() { return Err(e); }
            Ok(CdResponse::NotRegistered)
        }
        async fn ls(&self) -> anyhow::Result<LsResponse> {
            self.ls_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(e) = self.check_fail() { return Err(e); }
            Ok(LsResponse { projects: vec![] })
        }
        async fn start(&self, _: PathBuf) -> anyhow::Result<StartResponse> {
            if let Some(e) = self.check_fail() { return Err(e); }
            Ok(StartResponse::Spawning)
        }
        async fn stop(&self, _: PathBuf) -> anyhow::Result<()> {
            if let Some(e) = self.check_fail() { return Err(e); }
            Ok(())
        }
        async fn status(&self) -> anyhow::Result<StatusResponse> {
            if let Some(e) = self.check_fail() { return Err(e); }
            Ok(StatusResponse { registry_size: 0, active: 0, lru_cap: 8 })
        }
        async fn heartbeat(&self, _: PathBuf) -> anyhow::Result<()> {
            if let Some(e) = self.check_fail() { return Err(e); }
            Ok(())
        }
    }

    async fn raw_round_trip(sock_path: &std::path::Path, request_line: &str) -> String {
        let mut sock = ClientStream::connect(sock_path).await.unwrap();
        sock.write_all(request_line.as_bytes()).await.unwrap();
        sock.flush().await.unwrap();
        let mut lines = BufReader::new(sock).lines();
        lines.next_line().await.unwrap().unwrap()
    }

    #[tokio::test]
    async fn dispatches_ls_to_handler() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let line = raw_round_trip(&p, "{\"op\":\"ls\",\"args\":{}}\n").await;
        assert!(line.contains(r#""ok":true"#));
        assert!(line.contains(r#""projects":[]"#));
        assert_eq!(handler.ls_calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn dispatches_cd_with_args() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let line = raw_round_trip(&p, "{\"op\":\"cd\",\"args\":{\"cwd\":\"/x\"}}\n").await;
        assert!(line.contains(r#""ok":true"#));
        assert!(line.contains(r#""outcome":"not_registered""#));
        assert_eq!(handler.cd_calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn handler_err_becomes_wire_error() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        handler.fail_next.store(1, Ordering::SeqCst);
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let line = raw_round_trip(&p, "{\"op\":\"ls\",\"args\":{}}\n").await;
        assert!(line.contains(r#""ok":false"#));
        assert!(line.contains("mock failure"));
    }

    #[tokio::test]
    async fn malformed_request_yields_error_and_keeps_connection() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let mut sock = ClientStream::connect(&p).await.unwrap();
        sock.write_all(b"not json\n").await.unwrap();
        sock.write_all(b"{\"op\":\"ls\",\"args\":{}}\n").await.unwrap();
        sock.flush().await.unwrap();
        let mut lines = BufReader::new(sock).lines();
        let l1 = lines.next_line().await.unwrap().unwrap();
        assert!(l1.contains("bad request"));
        let l2 = lines.next_line().await.unwrap().unwrap();
        assert!(l2.contains(r#""ok":true"#));
    }
}
```

- [x] **Step 4: Update `crates/beansd-rpc/src/lib.rs`**

Replace contents:

```rust
mod server;
mod socket;
mod types;
mod wire;

pub use server::{Handler, serve};
pub use socket::{bind_uds, default_socket_path};
pub use types::*;
pub use wire::{WireRequest, WireResponse};
```

- [x] **Step 5: Run beansd-rpc tests**

```bash
nix develop --command cargo test --manifest-path Cargo.toml -p beansd-rpc
```

Expected: 4 wire tests + 3 socket tests + 6 types tests + 4 server tests = 17 tests pass.

- [x] **Step 6: Run the full workspace test suite**

```bash
nix develop --command cargo test --manifest-path Cargo.toml --workspace
```

Expected: 71 tests pass total (54 daemon + 17 beansd-rpc — Task 2 already moved 7 tests over).

- [x] **Step 7: Commit**

```bash
git add Cargo.lock crates/beansd-rpc/
git commit -m "crates/beansd-rpc: typed messages + Handler trait + serve"
```

## Summary of Changes

- Added `async-trait` dependency to `crates/beansd-rpc/Cargo.toml`.
- New `crates/beansd-rpc/src/types.rs` — typed response messages (`ProjectState`, `ProjectSummary`, `CdResponse`, `LsResponse`, `StartResponse`, `StatusResponse`) with 6 round-trip serde tests.
- New `crates/beansd-rpc/src/server.rs` — `Handler` async trait + `serve` function that accepts UDS connections, dispatches typed `WireRequest`s, and wraps results in `WireResponse`. Includes a `MockHandler`-driven test fixture (4 tests covering happy paths, handler errors, and malformed requests on a persistent connection).
- `crates/beansd-rpc/src/lib.rs` re-exports `Handler`, `serve`, and the typed messages.
- Daemon untouched (`beansd` will adopt `Handler` + `serve` in `dotfiles-erte`).
- `cargo test --workspace` → 71 passing (54 beansd + 17 beansd-rpc).
