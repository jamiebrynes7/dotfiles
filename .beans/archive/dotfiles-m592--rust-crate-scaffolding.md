---
# dotfiles-m592
title: Rust crate scaffolding
status: completed
type: feature
priority: normal
created_at: 2026-05-03T14:31:49Z
updated_at: 2026-05-09T13:36:15Z
parent: dotfiles-nzsd
---

Set up the `packages/beans-daemon` Rust crate: `Cargo.toml` with all dependencies pinned, `src/main.rs` with a clap-based CLI scaffold, and a buildable `cargo build` baseline. Owns: `packages/beans-daemon/Cargo.toml`, `packages/beans-daemon/Cargo.lock`, `packages/beans-daemon/src/main.rs`, `packages/beans-daemon/src/cli.rs`.

## Summary of Changes

All four child tasks completed. The `packages/beans-daemon` crate is now scaffolded with:

- **Toolchain** (dotfiles-g2br): Rust toolchain available via the flake devShell.
- **Crate skeleton** (dotfiles-uzwl): `Cargo.toml` with dependencies pinned (clap, anyhow, tokio, axum, tracing, etc.), `Cargo.lock`, `[[bin]] beansd`, edition 2021.
- **CLI dispatcher** (dotfiles-qnpn): `src/cli.rs` defines `Cli` + `Command` enum covering `run`, `cd`, `ls`, `start`, `stop`, `status`. `main.rs` parses via clap and routes each subcommand to an `unimplemented!` stub referencing F7/F8.
- **Tracing init** (dotfiles-wyid): `src/logging.rs` exposes `init(default_level)` building an `EnvFilter` from `RUST_LOG` with fallback, installing the global subscriber via `try_init`.

`cargo test` passes (3/3); `cargo run -- --help` and `--version` render the expected output. The crate is a buildable baseline ready for downstream features (F7 client commands, F8 daemon entrypoint).
