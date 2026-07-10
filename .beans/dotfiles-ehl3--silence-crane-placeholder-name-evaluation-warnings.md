---
# dotfiles-ehl3
title: Silence crane placeholder-name evaluation warnings
status: completed
type: task
priority: low
created_at: 2026-06-11T10:28:18Z
updated_at: 2026-07-10T16:36:04Z
---

Since the Rust build moved onto crane, `nix` evaluation emits a warning:

> crane will use a placeholder value since `name` cannot be found in <store>/Cargo.toml

## Cause

`crates/default.nix` defines a shared `commonArgs` set with no `pname`. It is consumed by:

- `cargoArtifacts = craneLib.buildDepsOnly commonArgs;`
- the `rust-*` checks (`cargoFmt`, `cargoClippy`, `cargoNextest`) which inherit `commonArgs`

The repo root `Cargo.toml` is a *virtual* workspace manifest (`[workspace]` only, no `[package].name`), so crane can't infer a crate name and substitutes a placeholder, warning each time.

`buildLocalRustBin` already passes an explicit `pname`, so the shipped package itself does not warn — only the deps-cache and check derivations do.

## Suggested fix

Set an explicit name on the shared args so crane stops guessing. Options (per the crane warning text):

- [x] Add `pname` (+ maybe `version`) to `commonArgs` in `crates/default.nix` — simplest; gives the deps cache / checks a stable name
- [ ] Or set `workspace.metadata.crane.name = "..."` in the root `Cargo.toml`
- [x] Verify `nix flake check` is warning-free afterwards (e.g. `NIX_ABORT_ON_WARN=1 nix --option pure-eval false --show-trace ...` to confirm no remaining sources)

## Summary of Changes

Silenced crane's `name cannot be found` evaluation warning that fired during `nix flake check`.

- Added explicit `pname = "dotfiles-rs-workspace"` and `version = "0.1.0"` to the shared `commonArgs` in `crates/default.nix`, so crane no longer substitutes a placeholder for the deps-cache (`buildDepsOnly`) and the `rust-clippy`/`rust-test` checks.
- Also passed `pname`/`version` to the `rust-fmt` (`cargoFmt`) call, which only inherited `src` from `commonArgs` and so still warned.
- `buildLocalRustBin` still overrides pname/version with the shipped package's own values, so `beans-daemon` is unchanged; the new name only labels the deps/check derivations.

Verified all four derivations (rust-clippy, rust-test, rust-fmt, beans-daemon) are warning-free and `nix flake check` passes.
