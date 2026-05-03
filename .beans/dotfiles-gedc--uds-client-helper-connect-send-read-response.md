---
# dotfiles-gedc
title: UDS client helper (connect + send + read response)
status: todo
type: task
created_at: 2026-05-03T14:40:19Z
updated_at: 2026-05-03T14:40:19Z
parent: dotfiles-cdo6
---

**Files:**
- Create: `packages/beans-daemon/src/cli_client.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod cli_client;`)

- [ ] **Step 1: Write the test**

Create `packages/beans-daemon/src/cli_client.rs`:
```rust
use crate::protocol::{Request, Response};
use anyhow::Context;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;

/// Send a request over the UDS and read one response. Used by ls/start/stop/status.
pub fn request(socket: &Path, req: &Request) -> anyhow::Result<Response> {
    let mut sock = UnixStream::connect(socket).with_context(|| format!("connecting {}", socket.display()))?;
    let mut buf = serde_json::to_vec(req)?; buf.push(b'\\n');
    sock.write_all(&buf)?;
    sock.shutdown(std::net::Shutdown::Write)?;
    let mut line = String::new();
    BufReader::new(sock).read_line(&mut line)?;
    Ok(serde_json::from_str(&line)?)
}

/// Fire-and-forget send. Used by `cd`. Silent on connection errors so the
/// shell prompt is never disturbed.
pub fn send_and_close(socket: &Path, req: &Request) {
    let Ok(mut sock) = UnixStream::connect(socket) else { return; };
    let Ok(mut buf) = serde_json::to_vec(req) else { return; }; buf.push(b'\\n');
    let _ = sock.write_all(&buf);
    let _ = sock.shutdown(std::net::Shutdown::Both);
}
```

- [ ] **Step 2: Run \`cargo build\`**

Run: `cargo build`
Expected: PASS — these are sync helpers, no test fixture needed yet.

(End-to-end coverage of the client comes via the F11 smoke test; the protocol round-trip test in F5 already exercises the wire format.)

- [ ] **Step 3: Wire into main.rs**

Add `mod cli_client;` to `packages/beans-daemon/src/main.rs`.

- [ ] **Step 4: Commit**

```bash
git add packages/beans-daemon/src/cli_client.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: UDS client helper for CLI subcommands"
```
