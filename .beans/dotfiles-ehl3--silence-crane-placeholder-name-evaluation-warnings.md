---
# dotfiles-ehl3
title: Silence crane placeholder-name evaluation warnings
status: todo
type: task
priority: low
created_at: 2026-06-11T10:28:18Z
updated_at: 2026-06-11T10:28:18Z
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

- [ ] Add `pname` (+ maybe `version`) to `commonArgs` in `crates/default.nix` — simplest; gives the deps cache / checks a stable name
- [ ] Or set `workspace.metadata.crane.name = "..."` in the root `Cargo.toml`
- [ ] Verify `nix flake check` is warning-free afterwards (e.g. `NIX_ABORT_ON_WARN=1 nix --option pure-eval false --show-trace ...` to confirm no remaining sources)
