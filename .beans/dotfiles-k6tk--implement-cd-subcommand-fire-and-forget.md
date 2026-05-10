---
# dotfiles-k6tk
title: Implement `cd` subcommand (fire-and-forget)
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:40:19Z
updated_at: 2026-05-10T13:50:56Z
parent: dotfiles-cdo6
---

**Files:**
- Modify: `packages/beans-daemon/src/main.rs`

- [x] **Step 1: Replace the `Cd` arm of the dispatcher**

In `packages/beans-daemon/src/main.rs`, replace:
```rust
        cli::Command::Cd { .. }     => unimplemented!("cd client — see F7"),
```
with:
```rust
        cli::Command::Cd { dir } => {
            let socket = control::default_socket_path()?;
            cli_client::send_and_close(&socket, &protocol::Request::Cd { cwd: dir });
            Ok(())
        }
```

You'll need `mod control;` and `mod cli_client;` and `mod protocol;` declared at the top — those should already be in place from earlier tasks.

- [x] **Step 2: Smoke test by hand**

Run (with no daemon running):
```bash
cargo run -- cd /tmp
echo "exit code: \$?"
```
Expected: exit 0, no output. (The socket isn't there, so `send_and_close` silently no-ops.)

- [x] **Step 3: Commit**

```bash
git add packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: cd subcommand (fire-and-forget UDS send)"
```

## Summary of Changes

Wired `Cd { dir }` in `main.rs` to `control::default_socket_path()` + `cli_client::send_and_close(&socket, &Request::Cd { cwd: dir })`. Smoke-tested with no daemon running: `cargo run -- cd /tmp` exits 0 silently as designed.
