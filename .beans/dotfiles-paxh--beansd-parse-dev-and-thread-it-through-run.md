---
# dotfiles-paxh
title: 'beansd: parse --dev and thread it through run()'
status: completed
type: task
priority: normal
created_at: 2026-05-30T18:33:16Z
updated_at: 2026-05-31T14:34:48Z
parent: dotfiles-spyq
blocked_by:
    - dotfiles-3531
    - dotfiles-hm5p
---

`beansd` has no argument parsing today (`main()` just builds a runtime and calls `run::run()`). Add a minimal clap parser for `--dev`, give `run()` a `dev: bool` parameter, and replace the two temporary `false` literals (added in earlier tasks) with the real flag value.

**Files:**
- Modify: `crates/beansd/src/main.rs` (clap `Cli`, pass `dev` to `run`)
- Modify: `crates/beansd/src/run.rs:13,14,37` (`run(dev)` signature + thread `dev`)

Depends on the socket and config tasks: `default_socket_path(dev)`, `Config::default_path(dev)`, and `resolve_beans_serve()` must already exist.

- [x] **Step 1: Add the clap parser to main.rs**

In `crates/beansd/src/main.rs`, keep the existing `mod` declarations and replace the `use`/`main` section so the file reads:

```rust
use clap::Parser;

#[derive(Parser)]
#[command(name = "beansd", version)]
struct Cli {
    /// Use the dev instance: dev socket + repo-local dev-config.toml.
    #[arg(long)]
    dev: bool,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(run::run(cli.dev))
}
```

(`clap` with the `derive` feature is already a dependency of `beansd`.)

- [x] **Step 2: Give `run` the `dev` parameter and thread it**

In `crates/beansd/src/run.rs`, change the signature on line 13:

```rust
pub async fn run(dev: bool) -> anyhow::Result<()> {
```

Then replace the two `false` literals previously inserted:

- line 14: `let cfg = Config::load(&Config::default_path(dev)?)?;`
- line 37: `let uds_path = default_socket_path(dev)?;`

- [x] **Step 3: Build the workspace**

Run: `cargo build --workspace`
Expected: success.

- [x] **Step 4: Smoke-test that --dev parses and is wired** (verified: sock-dev, port=9001, beans-serve resolved from \$PATH; beansctl --dev status round-trips)

Run: `cargo run -p beansd -- --help`
Expected: help output lists `--dev`.

Run: `cargo run -p beansd -- --dev` in one terminal; expect log lines showing the dev socket path (`sock-dev`) and `port=9001`. Stop it with Ctrl-C. (If `beans-serve` isn't on `$PATH`, expect the clear "beans-serve not found on $PATH" error instead — that still proves the dev config + resolution path are wired.)

- [x] **Step 5: Run the test suite**

Run: `cargo test -p beansd`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add crates/beansd/src/main.rs crates/beansd/src/run.rs
git commit -m "crates beansd: parse --dev and select the dev instance (dotfiles-z3aj)"
```

## Summary of Changes

`beansd` now parses a minimal clap `Cli` with a single `--dev` flag and threads `cli.dev` into `run::run(dev)`. `run()` passes `dev` to both `Config::default_path` and `default_socket_path`, replacing the temporary `false` literals from earlier tasks. Verified at runtime: `beansd --dev` loads dev-config.toml (port 9001), binds `sock-dev`, resolves `beans-serve` from `$PATH`, and `beansctl --dev status` round-trips to it.
