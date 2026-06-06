# Rust Workspace (`crates/`)

Freshness: 2026-06-06

## Purpose

Cargo workspace housing the `beans` issue tracker referenced throughout this repo:
a daemon, its control CLI, and a shared RPC library. Built and shipped via Nix
using [crane](https://github.com/ipetkov/crane); CI runs `nix flake check`, which
formats, lints, builds, and tests the whole workspace (see Commands).

The Nix build/check wiring lives in `crates/default.nix` — an overlay fragment
(kept out of `flake.nix` so the flake stays Rust-agnostic) that holds the toolchain
split, crane lib, shared `cargoArtifacts`, and the `rust-*` checks, and exports a
`buildLocalRustBin { pname; bins; ... }` helper. `packages/beans-daemon/default.nix`
is a one-liner over that helper.

## Workspace Layout

| Crate        | Kind | Purpose                                                                                         |
| ------------ | ---- | ----------------------------------------------------------------------------------------------- |
| `beansd`     | bin  | Background daemon — project registry, supervision, LRU eviction, HTTP launcher UI, UDS RPC server |
| `beansctl`   | bin  | Thin CLI that speaks UDS RPC to `beansd` (single `main.rs`, no submodules)                      |
| `beansd-rpc` | lib  | Shared wire types, `Handler` trait, UDS bind/serve helpers — the contract between the binaries  |

## Workspace Config

- `resolver = 2`, `edition = "2021"` (workspace-inherited via `[workspace.package]`).
- Shared deps live in `[workspace.dependencies]` in the root `Cargo.toml`. New
  crates should pull them via `<dep>.workspace = true` rather than re-pinning a
  version.
- `Cargo.lock` is committed (it's a binary workspace) — keep it that way.

## Commands

- `cargo build --workspace` / `cargo test --workspace` — run from repo root.
- `cargo test -p <crate>` — single crate.
- `nix flake check` — what CI runs (`.github/workflows/ci.yml`). Via crane, it runs
  the full loop as separate flake checks, sharing one `cargoArtifacts` deps build:
  - `beans-daemon` — `cargo build --bin beansd --bin beansctl` (the shipped package; `doCheck = false`)
  - `rust-fmt` — `cargo fmt --check`
  - `rust-clippy` — `cargo clippy --workspace --all-targets -- -D warnings`
  - `rust-test` — `cargo nextest run --workspace`

  The `rust-*` checks are workspace-wide (every crate), not specific to the
  `beans-daemon` package.

  Reproduce a single gate locally with `cargo fmt --check` / `cargo clippy
  --workspace --all-targets -- -D warnings` in the devShell.

No `justfile` / `Makefile`; don't introduce one unless asked.

### Dev instance (`--dev`)

To run a dev `beansd` alongside the launchd-managed prod daemon on the same
machine, pass `--dev` to both binaries. It selects a separate socket
(`…/sock-dev`) and the repo-local `crates/beansd/dev-config.toml` (launcher port
9001, `beans_serve_path` resolved from `$PATH`). Prod and the chpwd/prime hooks
never pass `--dev`, so they're untouched.

    cargo run -p beansd  -- --dev          # dev daemon (sock-dev, port 9001)
    cargo run -p beansctl -- --dev status  # dev CLI -> dev daemon

`beans-serve` must be on `$PATH` (it is, via the home-manager `beans` package).

## Conventions

- **Errors:** `anyhow::Result<T>`, `anyhow::bail!`, `anyhow::anyhow!`. Wrap
  boundary calls with `.with_context(|| ...)` (see
  `crates/beansd-rpc/src/client.rs:27`).
- **Async:** `tokio` (workspace, "full" features). Use `#[async_trait]` for traits
  with async methods (e.g. `Handler` in `beansd-rpc`).
- **Logging:** `tracing` + `tracing-subscriber` with `EnvFilter`. Initialised once
  per process in `crates/beansd/src/logging.rs`. Use
  `tracing::{info, warn, error}!` with structured fields; control verbosity via
  `RUST_LOG`.
- **Module style:** existing crates use a flat file-as-module layout
  (`mod foo;` → `src/foo.rs`); `mod.rs`-style directories are fine when a module
  grows enough to warrant submodules. Library crates re-export their public
  surface from `lib.rs` via `pub use` (see `crates/beansd-rpc/src/lib.rs:7-10`).
- **Tests:** colocated `#[cfg(test)] mod tests` in the same file as the code
  under test. `#[tokio::test]` for async. Cross-crate / full-stack tests go under
  `crates/<crate>/tests/` (see `crates/beansd-rpc/tests/round_trip.rs`).
- **Test helpers:** mock / fake implementations of traits live in a
  `mod test_utils` (gated on `#[cfg(test)]`, or behind a `test-utils` feature
  when shared across crates) rather than being redefined inline in each test
  file.
- **Lints / formatting:** no `rustfmt.toml`, no `clippy.toml`, no
  `[workspace.lints]`. Defaults only, but CI runs `clippy` with `-D warnings`
  (all warnings, including rustc lints like `dead_code`, are hard errors). Use a
  scoped `#[allow(...)]` with a comment for deliberate exceptions. Raise
  introducing a config file with the user first.

## Boundaries

- The Nix package (`packages/beans-daemon/default.nix`) is scoped to the named bins
  it passes to `buildLocalRustBin` (`--bin beansd --bin beansctl`). The fmt/clippy/test
  checks and the shared `cargoArtifacts` stay `--workspace` (see `crates/default.nix`).
  A new shipped binary means adding it to that `bins` list.
- Check `[workspace.dependencies]` before adding a dep to a single crate's
  `Cargo.toml` — prefer inheriting over re-pinning.