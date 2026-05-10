---
# dotfiles-1w3a
title: Define request/response envelope (`Op` enum + serde)
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:38:16Z
updated_at: 2026-05-10T13:36:32Z
parent: dotfiles-2ecf
---

**Files:**
- Create: `packages/beans-daemon/src/protocol.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod protocol;`)

Newline-delimited JSON, one message per line. Per spec §2: ops are `cd`, `ls`, `start`, `stop`, `status`, `heartbeat`.

- [x] **Step 1: Write the failing test**

Create `packages/beans-daemon/src/protocol.rs`:
```rust
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
#[serde(tag = "op", content = "args", rename_all = "snake_case")]
pub enum Request {
    Cd        { cwd: PathBuf },
    Ls        {},
    Start     { key: PathBuf },
    Stop      { key: PathBuf },
    Status    {},
    Heartbeat { key: PathBuf },
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum Response {
    Ok    { ok: bool, data: serde_json::Value },     // ok = true
    Error { ok: bool, error: String },               // ok = false
}

impl Response {
    pub fn ok(data: serde_json::Value) -> Self {
        Response::Ok { ok: true, data }
    }
    pub fn err(msg: impl Into<String>) -> Self {
        Response::Error { ok: false, error: msg.into() }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn round_trips_cd_request() {
        let r = Request::Cd { cwd: PathBuf::from("/abs/path") };
        let s = serde_json::to_string(&r).unwrap();
        assert_eq!(s, r#"{"op":"cd","args":{"cwd":"/abs/path"}}"#);
        let back: Request = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn round_trips_ls_request_with_empty_args() {
        let r = Request::Ls {};
        let s = serde_json::to_string(&r).unwrap();
        assert_eq!(s, r#"{"op":"ls","args":{}}"#);
        let back: Request = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn ok_response_serialises_with_ok_true() {
        let s = serde_json::to_string(&Response::ok(json!({"x": 1}))).unwrap();
        assert!(s.contains(r#""ok":true"#));
        assert!(s.contains(r#""x":1"#));
    }

    #[test]
    fn err_response_serialises_with_ok_false() {
        let s = serde_json::to_string(&Response::err("boom")).unwrap();
        assert!(s.contains(r#""ok":false"#));
        assert!(s.contains(r#""error":"boom""#));
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cargo test protocol::`
Expected: FAIL — module not declared.

- [x] **Step 3: Wire into main.rs**

Add `mod protocol;`.

- [x] **Step 4: Run tests**

Run: `cargo test protocol::`
Expected: 4 tests pass.

- [x] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/protocol.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: UDS request/response envelope types"
```

## Summary of Changes

Added `packages/beans-daemon/src/protocol.rs` defining the newline-delimited JSON envelope for the UDS control plane: `Request` enum (`cd`, `ls`, `start`, `stop`, `status`, `heartbeat`) tagged on `op` with `args` content, and `Response` with untagged `Ok { ok: true, data }` / `Error { ok: false, error }` variants plus `ok()` / `err()` constructors. Wired into `main.rs` via `mod protocol;`. Four unit tests cover round-trip and ok/err serialisation.
