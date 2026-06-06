---
# dotfiles-oqxj
title: Extract Rust build/check wiring from flake.nix into crates/
status: todo
type: task
created_at: 2026-06-06T20:22:03Z
updated_at: 2026-06-06T20:22:03Z
parent: dotfiles-ubfq
---

Follow-up to dotfiles-u7oa (crane migration). The `dotfilesOverlay` in `flake.nix` now carries a fair amount of Rust-specific wiring: `buildToolchain`/`rustToolchain`, `craneLib`, `commonArgs` (src fileset, libiconv, cargoExtraArgs), `cargoArtifacts`, and the `rustChecks` set. This bloats the top-level flake with crate-build concerns.

## Goal

Investigate moving the Rust-specific build/check logic out of `flake.nix` into a colocated module under `crates/` (e.g. `crates/default.nix`), so `flake.nix` just imports it and wires the results into `packages`/`checks`/`devShells`. Keep the workspace's build definition next to the workspace.

## Open questions / things to check

- **Feasibility of the path.** The overlay derives the toolchain from `rustyPkgs.rust-bin.*` (rust-overlay applied to `prev`), and `craneLib` needs `inputs.crane` + a pkgs instance. A `crates/default.nix` would need those passed in (e.g. `import ./crates { inherit pkgs inputs; }` or via `callPackage` with extra args). Confirm the cleanest plumbing.
- **What stays vs moves.** The devShell still needs the fat `rustToolchain` (rust-src/rust-analyzer) + `RUST_SRC_PATH`; decide whether that lives in `crates/` and is re-exported, or stays in `flake.nix`.
- **Discovery interaction.** `packages/beans-daemon/default.nix` is auto-discovered by `discoverPackages ./packages`. If the package build moves under `crates/`, reconcile with the discovery mechanism (or keep the package thunk in `packages/` and only move the shared `craneLib`/`commonArgs`/`cargoArtifacts`/`rustChecks` derivation logic).
- **`internal` attr.** Today the overlay exposes `dotfiles.internal.{rustToolchain,rustChecks}`. Preserve whatever the devShell/checks consume.

## Acceptance

- `flake.nix` no longer holds crate-specific build details (toolchain split, crane lib, commonArgs, cargoArtifacts, rustChecks) — they live under `crates/`.
- `nix flake check` still green; package closure unchanged (~51 MiB, libiconv only); the `rust-fmt`/`rust-clippy`/`rust-test` checks and `beans-daemon` package still present in `nix flake show`.
- devShell still exposes the fat toolchain + `RUST_SRC_PATH`.

## Out of Scope

- Behavioral changes to the build/checks — this is a pure relocation/refactor.

## Notes

If relocation proves awkward (e.g. overlay `final`/`prev` plumbing makes it uglier than it's worth), it's acceptable to scrap with a recorded rationale rather than force it.
