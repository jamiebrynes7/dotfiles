---
# dotfiles-bl8w
title: 'UDS server loop: accept connections, parse requests, dispatch'
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:38:16Z
updated_at: 2026-05-10T13:46:00Z
parent: dotfiles-2ecf
---

**Files:**
- Modify: `packages/beans-daemon/src/control.rs`

This wires the previous pieces into a runnable server loop. Per spec §2: newline-delimited JSON, one message per line. The `cd` client may close the write half before reading the response.

- [x] **Step 1: Write the test**

Append to `packages/beans-daemon/src/control.rs`:
```rust
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

impl<S: ChildSpawner + 'static> Daemon<S> {
    /// Run the UDS accept loop. Each accepted connection is handled on a
    /// fresh tokio task; one connection may carry many requests, one per line.
    pub async fn serve_uds(self: Arc<Self>, listener: tokio::net::UnixListener) -> anyhow::Result<()> {
        loop {
            let (sock, _addr) = listener.accept().await?;
            let me = self.clone();
            tokio::spawn(async move {
                if let Err(e) = me.handle_connection(sock).await {
                    tracing::warn!(error = ?e, "UDS connection ended with error");
                }
            });
        }
    }

    async fn handle_connection(&self, sock: tokio::net::UnixStream) -> anyhow::Result<()> {
        use crate::protocol::{Request, Response};
        let (rd, mut wr) = sock.into_split();
        let mut lines = BufReader::new(rd).lines();
        while let Some(line) = lines.next_line().await? {
            let req: Request = match serde_json::from_str(&line) {
                Ok(r) => r,
                Err(e) => {
                    let resp = Response::err(format!("bad request: {e}"));
                    let mut buf = serde_json::to_vec(&resp)?; buf.push(b'\\n');
                    let _ = wr.write_all(&buf).await;
                    continue;
                }
            };
            let data = match req {
                Request::Cd        { cwd } => self.handle_cd(cwd).await,
                Request::Ls        { }    => self.handle_ls().await,
                Request::Start     { key } => self.handle_start(key).await,
                Request::Stop      { key } => self.handle_stop(key).await,
                Request::Status    { }    => self.handle_status().await,
                Request::Heartbeat { key } => self.handle_heartbeat(key).await,
            };
            let resp = Response::ok(data);
            let mut buf = serde_json::to_vec(&resp)?; buf.push(b'\\n');
            // Best-effort: client may have already closed the write half
            // (fire-and-forget cd). Don't propagate broken-pipe errors.
            let _ = wr.write_all(&buf).await;
        }
        Ok(())
    }
}

#[cfg(test)]
mod uds_loop_tests {
    use super::*;
    use super::cd_tests::*;
    use crate::protocol::Request;
    use tempfile::tempdir;

    #[tokio::test]
    async fn round_trip_cd_via_uds() {
        let sock_dir = tempdir().unwrap();
        let sock_path = sock_dir.path().join("sock");
        let listener = bind_uds(&sock_path).unwrap();

        let registry = Arc::new(Mutex::new(Registry::new()));
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner:  ImmediateHealthy,
            health_timeout: Duration::from_secs(1),
        });
        let daemon = Arc::new(Daemon {
            registry: registry.clone(), supervisor, lru_cap: 8,
            sigterm_grace: Duration::from_secs(5),
            sigkill_grace: Duration::from_secs(5),
            start_max_attempts: 1,
            start_base_backoff: Duration::from_millis(10),
        });
        tokio::spawn(daemon.clone().serve_uds(listener));

        let dir = tempdir().unwrap();  // no .beans.yml → registered: false
        let req = Request::Cd { cwd: dir.path().to_path_buf() };
        let mut buf = serde_json::to_vec(&req).unwrap(); buf.push(b'\\n');

        let mut sock = tokio::net::UnixStream::connect(&sock_path).await.unwrap();
        sock.write_all(&buf).await.unwrap();
        sock.flush().await.unwrap();

        let mut lines = BufReader::new(sock).lines();
        let line = lines.next_line().await.unwrap().unwrap();
        assert!(line.contains(r#""ok":true"#));
        assert!(line.contains(r#""registered":false"#));
    }
}
```

- [x] **Step 2: Run tests**

Run: `cargo test control::uds_loop_tests`
Expected: PASS within 1 s.

- [x] **Step 3: Commit**

```bash
git add packages/beans-daemon/src/control.rs
git commit -m "packages/beans-daemon: UDS accept loop with newline-JSON dispatch"
```

## Summary of Changes

Added `serve_uds(self: Arc<Self>, listener)` and `handle_connection` to `Daemon` in `control.rs`. Each accepted connection runs on its own tokio task. Per-line newline-delimited JSON: parse → dispatch via `match` over the `Request` enum → respond with `ok` envelope. Malformed lines → `Response::err("bad request: …")` and continue. Writes use `write_all` ignoring errors so a fire-and-forget `cd` client closing the read half doesn't propagate. Two integration tests via real UDS socket: `cd` round-trip with no marker (`registered:false`) and a malformed-line response.
