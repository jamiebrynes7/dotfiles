---
# dotfiles-8szg
title: Implement `ls`, `start`, `stop`, `status` subcommands
status: todo
type: task
created_at: 2026-05-03T14:40:19Z
updated_at: 2026-05-03T14:40:19Z
parent: dotfiles-cdo6
---

**Files:**
- Modify: `packages/beans-daemon/src/main.rs`

- [ ] **Step 1: Replace the four arms**

In `packages/beans-daemon/src/main.rs`:
```rust
        cli::Command::Ls => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Ls {})?;
            print_response("ls", &resp);
            Ok(())
        }
        cli::Command::Start { key } => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Start { key })?;
            print_response("start", &resp);
            Ok(())
        }
        cli::Command::Stop { key } => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Stop { key })?;
            print_response("stop", &resp);
            Ok(())
        }
        cli::Command::Status => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Status {})?;
            print_response("status", &resp);
            Ok(())
        }
```

Add this helper near the bottom of `main.rs`:
```rust
fn print_response(label: &str, resp: &protocol::Response) {
    match resp {
        protocol::Response::Ok    { data, .. } => {
            println!("{}", serde_json::to_string_pretty(data).unwrap_or_default());
        }
        protocol::Response::Error { error, .. } => {
            eprintln!("beansd {label}: {error}");
            std::process::exit(1);
        }
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cargo build`
Expected: PASS — no `unimplemented!` arms remain in the dispatcher.

- [ ] **Step 3: Commit**

```bash
git add packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: ls/start/stop/status CLI subcommands"
```
