---
# dotfiles-u222
title: Port allocator (`127.0.0.1:0` ephemeral pick)
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:36:25Z
updated_at: 2026-05-09T14:04:24Z
parent: dotfiles-pmk6
---

**Files:**
- Create: `packages/beans-daemon/src/port_alloc.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod port_alloc;`)

The race window between bind/release and the child re-binding is accepted (spec §5). On child startup failure the supervisor will retry with a fresh port.

- [x] **Step 1: Write the failing test**

Create `packages/beans-daemon/src/port_alloc.rs`:
```rust
use std::net::TcpListener;

/// Pick an ephemeral loopback port by asking the kernel and immediately
/// dropping the listener. Returns the port the kernel chose.
pub fn pick_loopback_port() -> std::io::Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    drop(listener);
    Ok(port)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_a_nonzero_port() {
        let p = pick_loopback_port().unwrap();
        assert!(p > 0);
    }

    #[test]
    fn returns_distinct_ports_across_calls() {
        // Not strictly guaranteed by the OS (it could reuse), but in practice
        // the kernel hands out fresh ephemeral ports for back-to-back binds.
        // If this becomes flaky, drop the assertion and keep just the smoke test.
        let a = pick_loopback_port().unwrap();
        let b = pick_loopback_port().unwrap();
        assert_ne!(a, b, "expected distinct ephemeral ports; got {a} twice");
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cargo test port_alloc::`
Expected: FAIL — module not declared.

- [x] **Step 3: Wire into main.rs**

Add `mod port_alloc;` to `packages/beans-daemon/src/main.rs`.

- [x] **Step 4: Run tests**

Run: `cargo test port_alloc::`
Expected: 2 tests pass.

- [x] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/port_alloc.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: ephemeral loopback port picker"
```

## Summary of Changes

- Created `packages/beans-daemon/src/port_alloc.rs` with `pick_loopback_port()` (binds `127.0.0.1:0`, reads the assigned port, drops the listener).
- Wired `mod port_alloc;` into `packages/beans-daemon/src/main.rs`.
- `cargo test port_alloc::` → 2 passed (`picks_a_nonzero_port`, `returns_distinct_ports_across_calls`).
