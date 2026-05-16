---
# dotfiles-qu9y
title: Add Client + extract beansctl crate
status: completed
type: task
priority: normal
created_at: 2026-05-10T14:59:31Z
updated_at: 2026-05-16T07:45:34Z
parent: dotfiles-qwfb
blocked_by:
    - dotfiles-erte
---

**Files:**
- Create: `crates/beansd-rpc/src/client.rs` (sync `Client` with typed methods + edge-case error mapping)
- Create: `crates/beansd-rpc/tests/round_trip.rs` (integration test: real `bind_uds` + `serve(MockHandler)` + `Client::connect_to`)
- Create: `crates/beansctl/Cargo.toml`
- Create: `crates/beansctl/src/main.rs`
- Modify: `crates/beansd-rpc/src/lib.rs` (export `Client`)
- Modify: `crates/beansd-rpc/src/wire.rs` (tighten visibility from `pub` to `pub(crate)`)
- Modify: `crates/beansd-rpc/src/lib.rs` (drop `pub use wire::*`)
- Delete: `crates/beansd/src/cli_client.rs`
- Modify: `crates/beansd/src/main.rs` (delete `mod cli_client;`, drop the Cd/Ls/Start/Stop/Status arms; reduce to single-purpose daemon entrypoint)
- Modify: `crates/beansd/src/cli.rs` (drop the now-unused subcommand definitions, leaving the daemon binary with no subcommands)

After this task `beansd` is the daemon-only binary; `beansctl` is the user-facing CLI; the wire format is private to `beansd-rpc`.

- [x] **Step 1: Create `crates/beansd-rpc/src/client.rs`**

```rust
use crate::socket::default_socket_path;
use crate::types::{CdResponse, LsResponse, StartResponse, StatusResponse};
use crate::wire::{WireRequest, WireResponse};
use anyhow::Context;
use serde::de::DeserializeOwned;
use std::io::{BufRead, BufReader, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};

pub struct Client {
    socket: PathBuf,
}

impl Client {
    /// Probe the daemon at the default socket path. Returns Err if the
    /// daemon isn't reachable.
    pub fn connect() -> anyhow::Result<Self> {
        let path = default_socket_path()?;
        Self::connect_to(path)
    }

    /// Probe the daemon at a specific socket path.
    pub fn connect_to(socket: PathBuf) -> anyhow::Result<Self> {
        // Open + close a probe stream; surfaces unreachable errors at connect time.
        let _ = UnixStream::connect(&socket)
            .with_context(|| format!("connecting to daemon at {}", socket.display()))?;
        Ok(Self { socket })
    }

    /// Fire-and-forget: write the request, half-close the write side, return.
    /// The daemon writes a response which the kernel discards. Errors at
    /// connect / write surface here. Silencing for non-interactive callers
    /// (chpwd hook) is the shell wrapper's job.
    pub fn cd(&self, cwd: PathBuf) -> anyhow::Result<()> {
        let mut sock = UnixStream::connect(&self.socket)
            .with_context(|| format!("connecting to {}", self.socket.display()))?;
        let mut buf = serde_json::to_vec(&WireRequest::Cd { cwd })?;
        buf.push(b'\n');
        sock.write_all(&buf).context("rpc cd: writing request")?;
        sock.shutdown(Shutdown::Write).context("rpc cd: closing write half")?;
        Ok(())
    }

    pub fn ls(&self) -> anyhow::Result<LsResponse> {
        self.send(WireRequest::Ls {}, "ls")
    }

    pub fn start(&self, key: PathBuf) -> anyhow::Result<StartResponse> {
        self.send(WireRequest::Start { key }, "start")
    }

    pub fn stop(&self, key: PathBuf) -> anyhow::Result<()> {
        self.send::<serde_json::Value>(WireRequest::Stop { key }, "stop").map(|_| ())
    }

    pub fn status(&self) -> anyhow::Result<StatusResponse> {
        self.send(WireRequest::Status {}, "status")
    }

    pub fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()> {
        self.send::<serde_json::Value>(WireRequest::Heartbeat { key }, "heartbeat").map(|_| ())
    }

    fn send<T: DeserializeOwned>(&self, req: WireRequest, op: &'static str) -> anyhow::Result<T> {
        let mut sock = UnixStream::connect(&self.socket)
            .with_context(|| format!("rpc {op}: connecting to {}", self.socket.display()))?;
        let mut buf = serde_json::to_vec(&req)?;
        buf.push(b'\n');
        sock.write_all(&buf).with_context(|| format!("rpc {op}: writing request"))?;
        sock.shutdown(Shutdown::Write)
            .with_context(|| format!("rpc {op}: closing write half"))?;

        let mut line = String::new();
        let n = BufReader::new(sock)
            .read_line(&mut line)
            .with_context(|| format!("rpc {op}: reading response"))?;
        if n == 0 {
            anyhow::bail!("rpc {op}: daemon closed connection without responding");
        }
        let resp: WireResponse = serde_json::from_str(&line)
            .with_context(|| format!("rpc {op}: malformed response from daemon"))?;
        match resp {
            WireResponse::Ok { data, .. } => serde_json::from_value(data)
                .with_context(|| format!("rpc {op}: decoding response")),
            WireResponse::Error { error, .. } => Err(anyhow::anyhow!("{error}"))
                .with_context(|| format!("rpc {op}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader as TokioBufReader};
    use tokio::net::UnixListener;

    /// Stand up a tiny in-process UDS server that, on the first connection,
    /// reads one request line and writes the supplied response line.
    async fn echo_once(path: &Path, response: &'static [u8]) {
        let listener = UnixListener::bind(path).unwrap();
        tokio::spawn(async move {
            if let Ok((sock, _)) = listener.accept().await {
                let (rd, mut wr) = sock.into_split();
                let mut lines = TokioBufReader::new(rd).lines();
                let _ = lines.next_line().await;
                let _ = wr.write_all(response).await;
            }
        });
    }

    #[tokio::test]
    async fn ls_round_trip() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        echo_once(
            &p,
            b"{\"ok\":true,\"data\":{\"projects\":[]}}\n",
        )
        .await;
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;

        let path = p.clone();
        let resp = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.ls()
        })
        .await
        .unwrap()
        .unwrap();
        assert_eq!(resp.projects.len(), 0);
    }

    #[tokio::test]
    async fn empty_response_maps_to_friendly_error() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        // Server accepts then closes without writing.
        let listener = UnixListener::bind(&p).unwrap();
        tokio::spawn(async move {
            let _ = listener.accept().await;
            // drop listener and accepted stream
        });
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;

        let path = p.clone();
        let err = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.ls()
        })
        .await
        .unwrap()
        .unwrap_err();
        assert!(err.to_string().contains("daemon closed connection without responding"));
    }

    #[tokio::test]
    async fn malformed_response_maps_to_friendly_error() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        echo_once(&p, b"not json\n").await;
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;

        let path = p.clone();
        let err = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.ls()
        })
        .await
        .unwrap()
        .unwrap_err();
        assert!(format!("{err:#}").contains("malformed response from daemon"));
    }

    #[tokio::test]
    async fn wire_error_propagates_with_op_context() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        echo_once(&p, b"{\"ok\":false,\"error\":\"unknown project: /x\"}\n").await;
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;

        let path = p.clone();
        let err = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.start(PathBuf::from("/x"))
        })
        .await
        .unwrap()
        .unwrap_err();
        assert!(format!("{err:#}").contains("rpc start"));
        assert!(format!("{err:#}").contains("unknown project"));
    }

    #[tokio::test]
    async fn cd_does_not_read_response() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = UnixListener::bind(&p).unwrap();
        tokio::spawn(async move {
            // Accept and drop without writing — cd shouldn't care.
            let _ = listener.accept().await;
        });
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;

        let path = p.clone();
        let result = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.cd(PathBuf::from("/some/dir"))
        })
        .await
        .unwrap();
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn connect_to_missing_socket_errors() {
        let result = tokio::task::spawn_blocking(|| {
            Client::connect_to(PathBuf::from("/no/such/socket"))
        })
        .await
        .unwrap();
        assert!(result.is_err());
    }
}
```

- [x] **Step 2: Tighten wire-type visibility in `crates/beansd-rpc/src/wire.rs`**

Change the two top-level type declarations:

```rust
pub(crate) enum WireRequest { ... }
pub(crate) enum WireResponse { ... }
```

And the `impl WireResponse` constructors:

```rust
impl WireResponse {
    pub(crate) fn ok(data: serde_json::Value) -> Self { ... }
    pub(crate) fn err(msg: impl Into<String>) -> Self { ... }
}
```

(The fields' inline `pub` stays — `pub(crate)` enums automatically scope their variants.)

- [x] **Step 3: Update `crates/beansd-rpc/src/lib.rs`**

Replace contents:

```rust
mod client;
mod server;
mod socket;
mod types;
mod wire;

pub use client::Client;
pub use server::{Handler, serve};
pub use socket::{bind_uds, default_socket_path};
pub use types::*;
```

(`pub use wire::{WireRequest, WireResponse};` removed — they're internal now.)

- [x] **Step 4: Add the integration test `crates/beansd-rpc/tests/round_trip.rs`**

```rust
//! Real bind_uds + real serve(MockHandler) + real Client, one assertion per op.

use async_trait::async_trait;
use beansd_rpc::{
    bind_uds, serve, CdResponse, Client, Handler, LsResponse, ProjectState, ProjectSummary,
    StartResponse, StatusResponse,
};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use tempfile::tempdir;

struct MockHandler {
    cd_calls: AtomicUsize,
}

impl MockHandler {
    fn new() -> Self {
        Self { cd_calls: AtomicUsize::new(0) }
    }
}

#[async_trait]
impl Handler for MockHandler {
    async fn cd(&self, _cwd: PathBuf) -> anyhow::Result<CdResponse> {
        self.cd_calls.fetch_add(1, Ordering::SeqCst);
        Ok(CdResponse::NotRegistered)
    }
    async fn ls(&self) -> anyhow::Result<LsResponse> {
        Ok(LsResponse {
            projects: vec![ProjectSummary {
                key: PathBuf::from("/p"),
                display_name: "p".into(),
                state: ProjectState::Healthy,
                port: Some(4242),
            }],
        })
    }
    async fn start(&self, _: PathBuf) -> anyhow::Result<StartResponse> {
        Ok(StartResponse::AlreadyActive)
    }
    async fn stop(&self, key: PathBuf) -> anyhow::Result<()> {
        if key == Path::new("/missing") {
            anyhow::bail!("unknown project: /missing");
        }
        Ok(())
    }
    async fn status(&self) -> anyhow::Result<StatusResponse> {
        Ok(StatusResponse { registry_size: 1, active: 1, lru_cap: 8 })
    }
    async fn heartbeat(&self, _: PathBuf) -> anyhow::Result<()> { Ok(()) }
}

async fn boot() -> (PathBuf, tempfile::TempDir, Arc<MockHandler>) {
    let dir = tempdir().unwrap();
    let p = dir.path().join("sock");
    let listener = bind_uds(&p).unwrap();
    let handler = Arc::new(MockHandler::new());
    let h = handler.clone();
    tokio::spawn(async move { serve(listener, h).await });
    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    (p, dir, handler)
}

#[tokio::test]
async fn cd_round_trip() {
    let (p, _dir, handler) = boot().await;
    let p2 = p.clone();
    tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.cd(PathBuf::from("/some/dir")).unwrap();
    })
    .await
    .unwrap();
    // Tiny delay so the daemon-side dispatch task observes the call.
    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    assert_eq!(handler.cd_calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn ls_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.ls().unwrap()
    })
    .await
    .unwrap();
    assert_eq!(resp.projects.len(), 1);
    assert_eq!(resp.projects[0].port, Some(4242));
}

#[tokio::test]
async fn start_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.start(PathBuf::from("/p")).unwrap()
    })
    .await
    .unwrap();
    assert_eq!(resp, StartResponse::AlreadyActive);
}

#[tokio::test]
async fn stop_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let result = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.stop(PathBuf::from("/p"))
    })
    .await
    .unwrap();
    assert!(result.is_ok());
}

#[tokio::test]
async fn status_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.status().unwrap()
    })
    .await
    .unwrap();
    assert_eq!(resp.lru_cap, 8);
}

#[tokio::test]
async fn heartbeat_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let result = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.heartbeat(PathBuf::from("/p"))
    })
    .await
    .unwrap();
    assert!(result.is_ok());
}

#[tokio::test]
async fn handler_err_surfaces_with_rpc_context() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let err = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.stop(PathBuf::from("/missing"))
    })
    .await
    .unwrap()
    .unwrap_err();
    assert!(format!("{err:#}").contains("rpc stop"));
    assert!(format!("{err:#}").contains("unknown project"));
}
```

- [x] **Step 5: Create `crates/beansctl/Cargo.toml`**

```toml
[package]
name = "beansctl"
version.workspace = true
edition.workspace = true

[[bin]]
name = "beansctl"
path = "src/main.rs"

[dependencies]
anyhow.workspace = true
beansd-rpc = { path = "../beansd-rpc" }
clap = { version = "4", features = ["derive"] }
serde_json.workspace = true
```

- [x] **Step 6: Create `crates/beansctl/src/main.rs`**

```rust
use beansd_rpc::Client;
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "beansctl", version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(clap::Subcommand, Debug)]
enum Command {
    /// Register the current beans project (cd-hook target). Fire-and-forget.
    Cd { dir: PathBuf },
    /// List registered projects.
    Ls,
    /// Re-spawn a stopped or evicted project.
    Start { key: PathBuf },
    /// Trigger eviction of a running project.
    Stop { key: PathBuf },
    /// Print daemon status counters.
    Status,
    /// Bump a project's last_used timestamp.
    Heartbeat { key: PathBuf },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let client = Client::connect()?;
    match cli.command {
        Command::Cd { dir } => client.cd(dir),
        Command::Ls => print_pretty(&client.ls()?),
        Command::Start { key } => print_pretty(&client.start(key)?),
        Command::Stop { key } => client.stop(key),
        Command::Status => print_pretty(&client.status()?),
        Command::Heartbeat { key } => client.heartbeat(key),
    }
}

fn print_pretty<T: serde::Serialize>(value: &T) -> anyhow::Result<()> {
    println!("{}", serde_json::to_string_pretty(value)?);
    Ok(())
}
```

- [x] **Step 7: Delete `crates/beansd/src/cli_client.rs`**

```bash
git rm crates/beansd/src/cli_client.rs
```

- [x] **Step 8: Reduce `crates/beansd/src/cli.rs`**

Replace contents:

```rust
use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "beansd", version)]
pub struct Cli {}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn cli_definition_is_valid() {
        Cli::command().debug_assert();
    }
}
```

(All subcommands removed; the daemon binary takes no positional args.)

- [x] **Step 9: Reduce `crates/beansd/src/main.rs`**

Replace contents:

```rust
mod cli;
mod config;
mod daemon;
mod handler;
mod launcher;
mod logging;
mod port_alloc;
mod project_key;
mod registry;
mod run;
mod spawner;
mod supervisor;

use clap::Parser;

fn main() -> anyhow::Result<()> {
    let _ = cli::Cli::parse();
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(run::run())
}
```

(`mod cli_client;` removed; the `match cli.command` block reduced to `block_on(run::run())`.)

- [x] **Step 10: Run beansd-rpc tests (unit + integration)**

```bash
nix develop --command cargo test --manifest-path Cargo.toml -p beansd-rpc
```

Expected: previous beansd-rpc tests + 6 client unit tests + 7 round_trip integration tests pass.

- [x] **Step 11: Run the full workspace test suite**

```bash
nix develop --command cargo test --manifest-path Cargo.toml --workspace
```

Expected: full suite green.

- [x] **Step 12: Smoke-test the binaries**

```bash
nix develop --command cargo build --manifest-path Cargo.toml --workspace
ls target/debug/beansd target/debug/beansctl
```

Both binaries exist.

If a daemon is running on this machine: `target/debug/beansctl status` prints typed JSON.

- [x] **Step 13: Commit**

```bash
git add Cargo.lock crates/
git commit -m "crates/beansctl: extract CLI; beansd-rpc Client; tighten wire visibility"
```

## Summary of Changes

- New `crates/beansd-rpc/src/client.rs` — sync `Client` with typed methods (`cd`, `ls`, `start`, `stop`, `status`, `heartbeat`), op-tagged error context, and friendly error mapping for empty/malformed daemon responses. `connect_to` probes the socket so unreachable daemons fail fast at construction.
- New `crates/beansd-rpc/tests/round_trip.rs` — 7-op integration test against real `bind_uds` + `serve(MockHandler)` + `Client::connect_to`. Confirms each op round-trips Client → server → Handler → server → Client and that handler errors surface with `rpc <op>` context.
- New `crates/beansctl/` — daemon CLI binary with `cd|ls|start|stop|status|heartbeat` subcommands, depending only on `beansd-rpc`. Replaces the multi-mode beansd binary.
- `crates/beansd-rpc/src/wire.rs` — `WireRequest`/`WireResponse` and constructors tightened from `pub` to `pub(crate)`. Wire format is now private to `beansd-rpc`.
- `crates/beansd-rpc/src/lib.rs` — dropped `pub use wire::*`; added `pub use client::Client`.
- Deleted `crates/beansd/src/cli_client.rs`.
- `crates/beansd/src/cli.rs` — collapsed to an empty subcommand-less `Cli` struct.
- `crates/beansd/src/main.rs` — collapsed to `cli::Cli::parse()` + `block_on(run::run())`. `mod cli_client;` removed.
- `cargo test --workspace` → 80 passing (50 beansd + 23 beansd-rpc unit + 7 beansd-rpc integration).

## Notes / Deviations from Spec

- Added `serde.workspace = true` to `crates/beansctl/Cargo.toml`: required by `print_pretty<T: serde::Serialize>`, missing from the spec.
- Replaced the spec's single-accept `echo_once` test helper with looping helpers (`echo_responder`, `silent_responder`): the spec's helper conflicted with `Client::connect_to`'s probe, which consumes one accept before the real request.
