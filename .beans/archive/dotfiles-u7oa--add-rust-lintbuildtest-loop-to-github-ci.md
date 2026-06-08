---
# dotfiles-u7oa
title: Add fmt/clippy/test to nix flake check via crane
status: completed
type: task
priority: normal
created_at: 2026-05-24T15:18:14Z
updated_at: 2026-06-06T20:20:27Z
parent: dotfiles-ubfq
---

Today `.github/workflows/ci.yml` runs only `nix flake check`. At `flake.nix:185` that's `checks = self.packages`, so the only Rust gate is the `beans-daemon` package build. Missing:

- No `cargo clippy` lint gate
- No `cargo fmt --check` formatting gate

Goal: add fmt / clippy / test as first-class flake checks so `nix flake check` (the single thing CI runs) covers the full Rust lint → build → test loop, with shared build artifacts so it stays fast.

## Approach

Migrate `packages/beans-daemon` from `rustPlatform.buildRustPackage` to **crane**, reusing the existing pinned toolchain at `flake.nix:55` (`rust-bin.stable.latest.default` — `rustfmt` and `clippy` are already in the `default` profile, so no extra components needed).

Crane gives us:
- `craneLib.overrideToolchain rustToolchain` — same toolchain as the devShell + package, no drift
- `cargoArtifacts` (via `buildDepsOnly`) — deps built once, reused by every check
- `craneLib.cargoFmt` / `cargoClippy` / `cargoNextest` (or `cargoTest`) — drop-in check derivations

Wire each as `checks.<system>.{rustfmt,clippy,test}` so `nix flake check` runs them in parallel with artifact reuse. No `.github/workflows/ci.yml` change required — the existing `nix flake check` step picks them up.

## Todos

- [x] Add `crane` input to `flake.nix` (no `nixpkgs` to follow — modern crane is nixpkgs-agnostic)
- [x] Plumb `crane` through the overlay: `craneLib = (crane.mkLib final).overrideToolchain buildToolchain` (bare profile per d1qc coordination)
- [x] Define shared `commonArgs` (fileset src incl. crates assets, not cleanCargoSource — askama/.html/.css/.js) + `cargoArtifacts = craneLib.buildDepsOnly commonArgs`
- [x] Rewrite `packages/beans-daemon/default.nix` to `craneLib.buildPackage (commonArgs // {...})` — pname/version/meta preserved, `doCheck = false`
- [x] Add `checks.<system>.beans-daemon-fmt = craneLib.cargoFmt { inherit (commonArgs) src; }`
- [x] Add `checks.<system>.beans-daemon-clippy` (`--all-targets -- -D warnings`; `--workspace` via commonArgs.cargoExtraArgs)
- [x] Add `checks.<system>.beans-daemon-test = craneLib.cargoNextest` (89 tests pass)
- [x] `checks.<system>` merges `self.packages.<system>` with `dotfiles.internal.rustChecks` (package built once)
- [x] Verified: `nix flake check` green; fmt/clippy/test all appear in `nix flake show`; closure still 51.4 MiB (libiconv only)
- [x] Updated `crates/CLAUDE.md` (Purpose, Commands, Lints convention) + freshness 2026-06-06
- [x] Open PR; confirm CI green

## Out of Scope

- Introducing `[workspace.lints]` or `clippy.toml` (per `crates/CLAUDE.md`: raise with user first). Clippy uses defaults + `-D warnings` only.
- A separate `cargo` GitHub Actions job — `nix flake check` is the single source of truth.
- Cross-platform CI matrix (macOS); `ubuntu-latest` stays. Pinned toolchain keeps results deterministic across platforms locally.


## Coordination with closure slimming (dotfiles-d1qc)

When wiring `craneLib.overrideToolchain`, point it at the bare `default`-profile `buildToolchain` (no `rust-src`/`rust-analyzer`), **not** the fat devShell `rustToolchain` at `flake.nix:55`. `rustfmt` and `clippy` are in the `default` profile, so the crane checks still work, and this avoids re-bloating the `beans-daemon` runtime closure. See sibling bean dotfiles-d1qc for the full rationale.

## Summary of Changes

Migrated `packages/beans-daemon` from `rustPlatform.buildRustPackage` to **crane**, and added the full Rust lint→build→test loop as flake checks so `nix flake check` (the single CI gate) covers everything.

### flake.nix
- Added the `crane` input (no `nixpkgs.follows` — modern crane is nixpkgs-agnostic, reads pkgs at `crane.mkLib final`).
- `craneLib` pinned to the bare `buildToolchain` (per d1qc) so the package closure stays slim — verified still **51.4 MiB**, runtime ref = `libiconv` only.
- Shared `commonArgs` (src + `strictDeps` + `cargoExtraArgs = "--locked --workspace"` + darwin `libiconv`) feeding one `cargoArtifacts` deps build reused by the package and all checks.
- `src` is a full `fileset.toSource` of Cargo.{toml,lock}+crates, **not** `cleanCargoSource`: `beansd` embeds askama `.html` templates + `.css`/`.js` assets that the cargo-only filter strips (this was a real build failure).
- New `checks.<system>`: `rust-fmt`, `rust-clippy` (`--all-targets -- -D warnings`), `rust-test` (`cargoNextest`), merged with `self.packages` (package built once). Named `rust-*` (not `beans-daemon-*`) since `--workspace` covers every crate.

### packages/beans-daemon/default.nix
- Rewritten to `craneLib.buildPackage (commonArgs // {...})`; `doCheck = false` (tests run in the dedicated `rust-test` check); pname/version/meta preserved.

### Pre-existing lints fixed (exposed by the new `-D warnings` gate)
- 5× unneeded unit-variant struct patterns (`Spawning {..}`→`Spawning`, `Evicting {..}`→`Evicting`).
- `Server::serve` → idiomatic `async fn` (+ dropped now-unused `use std::future::Future`); still `Send + 'static` for `tokio::spawn`.
- `#[allow(dead_code)]` + comments on the deliberate-but-unconsumed `Config.heartbeat_secs` and `ProjectState::Dead.reason`.
- Removed the unused `MockHealthChecker::fail_first` helper and its orphaned `fail_first_n`/`calls` machinery, simplifying the mock to `!self.never_ready` (behavior-identical for existing tests).

### crates/CLAUDE.md
- Updated Purpose/Commands (the four checks, crane), Lints convention (`-D warnings`, scoped `#[allow]`), Boundaries (`--workspace` now via `commonArgs.cargoExtraArgs`); freshness → 2026-06-06.

Verified: `nix flake check` green on aarch64-darwin (89 tests via nextest); x86_64-linux check derivations evaluate cleanly (CI is the first real linux build).
