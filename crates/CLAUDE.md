# Rust Workspace (`crates/`)

Freshness: 2026-11-13

## Purpose

An empty Cargo workspace, kept ready for future crates (it previously held the
beans daemon; see git history). Crates are built and shipped via Nix using
[crane](https://github.com/ipetkov/crane).

The Nix build/check wiring lives in `crates/default.nix` — an overlay fragment
(kept out of `flake.nix` so the flake stays Rust-agnostic) that holds the toolchain
split, crane lib, shared `cargoArtifacts`, and the `rust-*` checks, and exports a
`buildLocalRustBin { pname; bins; ... }` helper. A shipped binary is a
`packages/<name>/default.nix` one-liner over that helper.

## Workspace Config

- `members = ["crates/*"]`: any `crates/<name>/` with a `Cargo.toml` joins the workspace.
- `resolver = 2`, `edition = "2021"` (workspace-inherited via `[workspace.package]`).
- Shared deps live in `[workspace.dependencies]` in the root `Cargo.toml`. New
  crates should pull them via `<dep>.workspace = true` rather than re-pinning a
  version.
- `Cargo.lock` is committed — keep it that way.

## Commands

- `cargo build --workspace` / `cargo test --workspace` — run from repo root.
  Cargo rejects a workspace with no members, so these fail until a crate exists.
- `cargo test -p <crate>` — single crate.
- `nix flake check` — what CI runs (`.github/workflows/ci.yml`). Via crane, it runs
  the workspace-wide gates as separate flake checks, sharing one `cargoArtifacts`
  deps build:
  - `rust-fmt` — `cargo fmt --check`
  - `rust-clippy` — `cargo clippy --workspace --all-targets -- -D warnings`
  - `rust-test` — `cargo nextest run --workspace`

  These checks only exist while some `crates/<name>/Cargo.toml` does (`hasCrates`
  in `crates/default.nix`); with no crates they are absent rather than red.

  Reproduce a single gate locally with `cargo fmt --check` / `cargo clippy
  --workspace --all-targets -- -D warnings` in the devShell.

No `justfile` / `Makefile`; don't introduce one unless asked.

## Conventions

- **Errors:** `anyhow::Result<T>`, `anyhow::bail!`, `anyhow::anyhow!`. Wrap
  boundary calls with `.with_context(|| ...)`.
- **Async:** `tokio` with `#[async_trait]` for traits with async methods.
- **Logging:** `tracing` + `tracing-subscriber` with `EnvFilter`, initialised
  once per process; control verbosity via `RUST_LOG`.
- **Module style:** flat file-as-module layout (`mod foo;` → `src/foo.rs`);
  `mod.rs`-style directories are fine when a module grows submodules. Library
  crates re-export their public surface from `lib.rs` via `pub use`.
- **Tests:** colocated `#[cfg(test)] mod tests` in the same file as the code
  under test. `#[tokio::test]` for async. Cross-crate / full-stack tests go under
  `crates/<crate>/tests/`.
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

- A package built with `buildLocalRustBin` is scoped to the bins it names
  (`--bin <name>` each). The fmt/clippy/test checks and the shared
  `cargoArtifacts` stay `--workspace` (see `crates/default.nix`).
- Check `[workspace.dependencies]` before adding a dep to a single crate's
  `Cargo.toml` — prefer inheriting over re-pinning.
