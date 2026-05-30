---
# dotfiles-o1zs
title: 'beansctl: add global --dev and route the client'
status: todo
type: task
priority: normal
created_at: 2026-05-30T18:33:34Z
updated_at: 2026-05-30T18:33:45Z
parent: dotfiles-spyq
blocked_by:
    - dotfiles-3531
---

Add a global `--dev` flag to `beansctl` so it can precede any subcommand, and connect to the dev socket when it's set.

**Files:**
- Modify: `crates/beansctl/src/main.rs` (add flag to `Cli`, branch the client connect)

Depends on `default_socket_path(dev)` already existing in `beansd-rpc`.

- [ ] **Step 1: Add the global flag to the `Cli` struct**

In `crates/beansctl/src/main.rs`, add a `dev` field to `Cli` (above the existing `command` field):

```rust
#[derive(Parser, Debug)]
#[command(name = "beansctl", version)]
struct Cli {
    /// Talk to the dev daemon (matches `beansd --dev`).
    #[arg(long, global = true)]
    dev: bool,
    #[command(subcommand)]
    command: Command,
}
```

- [ ] **Step 2: Route the client connection**

In `main()`, replace `let client = Client::connect()?;` with:

```rust
    let client = if cli.dev {
        Client::connect_to(beansd_rpc::default_socket_path(true)?)?
    } else {
        Client::connect()?
    };
```

(`Client::connect_to` and `beansd_rpc::default_socket_path` are both already public.)

- [ ] **Step 3: Build**

Run: `cargo build -p beansctl`
Expected: success.

- [ ] **Step 4: Smoke-test routing**

Run: `cargo run -p beansctl -- --help`
Expected: help lists `--dev` as a global option.

With a dev daemon running (`cargo run -p beansd -- --dev`), run:
`cargo run -p beansctl -- --dev status`
Expected: connects and prints status from the dev daemon. Without `--dev`, it would hit prod (or error if prod isn't running) — confirming the two are routed separately.

- [ ] **Step 5: Run tests**

Run: `cargo test --workspace`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add crates/beansctl/src/main.rs
git commit -m "crates beansctl: add --dev to target the dev daemon (dotfiles-z3aj)"
```
