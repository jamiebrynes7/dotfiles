---
# dotfiles-3531
title: 'default_socket_path: add dev flag + -dev suffix'
status: todo
type: task
created_at: 2026-05-30T18:32:06Z
updated_at: 2026-05-30T18:32:06Z
parent: dotfiles-vupf
---

Make the shared socket helper flavor-aware. Both binaries call this, so the dev daemon and dev CLI resolve the same `-dev` path with no other coordination. Update the two existing call sites to pass `false` so the workspace still compiles (the daemon's real `dev` value is threaded in a later task).

**Files:**
- Modify: `crates/beansd-rpc/src/socket.rs:6-14` (`default_socket_path`)
- Modify: `crates/beansd-rpc/src/client.rs:19` (caller passes `false`)
- Modify: `crates/beansd/src/run.rs:37` (caller passes `false`)
- Test: `crates/beansd-rpc/src/socket.rs` (colocated `#[cfg(test)] mod tests`)

- [ ] **Step 1: Write the failing test**

Add to the existing `mod tests` in `crates/beansd-rpc/src/socket.rs`:

```rust
#[test]
fn default_socket_path_dev_differs_from_prod() {
    // Set both vars so the call succeeds regardless of target_os.
    std::env::set_var("HOME", "/tmp/h");
    std::env::set_var("XDG_RUNTIME_DIR", "/tmp/r");
    let prod = default_socket_path(false).unwrap();
    let dev = default_socket_path(true).unwrap();
    assert_ne!(prod, dev);
    assert!(dev.file_name().unwrap().to_str().unwrap().contains("dev"));
    assert!(!prod.file_name().unwrap().to_str().unwrap().contains("dev"));
}
```

- [ ] **Step 2: Run the test, expect a compile error**

Run: `cargo test -p beansd-rpc default_socket_path_dev_differs_from_prod`
Expected: FAILS to compile — `default_socket_path` takes no arguments yet.

- [ ] **Step 3: Add the `dev` parameter and suffix logic**

Replace `default_socket_path` in `crates/beansd-rpc/src/socket.rs` with:

```rust
pub fn default_socket_path(dev: bool) -> anyhow::Result<PathBuf> {
    if cfg!(target_os = "macos") {
        let home = std::env::var("HOME").context("HOME unset")?;
        let name = if dev { "sock-dev" } else { "sock" };
        Ok(PathBuf::from(home).join(format!("Library/Caches/beans-daemon/{name}")))
    } else {
        let xdg = std::env::var("XDG_RUNTIME_DIR").context("XDG_RUNTIME_DIR unset")?;
        let name = if dev { "beans-daemon-dev.sock" } else { "beans-daemon.sock" };
        Ok(PathBuf::from(xdg).join(name))
    }
}
```

- [ ] **Step 4: Update the two existing call sites to pass `false`**

In `crates/beansd-rpc/src/client.rs:19`, inside `connect()`:

```rust
let path = default_socket_path(false)?;
```

In `crates/beansd/src/run.rs:37`:

```rust
let uds_path = default_socket_path(false)?;
```

- [ ] **Step 5: Run the test, expect pass**

Run: `cargo test -p beansd-rpc default_socket_path_dev_differs_from_prod`
Expected: PASS.

- [ ] **Step 6: Build the workspace to confirm call sites compile**

Run: `cargo build --workspace`
Expected: success, no errors.

- [ ] **Step 7: Commit**

```bash
git add crates/beansd-rpc/src/socket.rs crates/beansd-rpc/src/client.rs crates/beansd/src/run.rs
git commit -m "crates beansd-rpc: add dev flag to default_socket_path (dotfiles-z3aj)"
```
