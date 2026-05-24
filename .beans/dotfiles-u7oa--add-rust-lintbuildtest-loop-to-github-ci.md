---
# dotfiles-u7oa
title: Add fmt/clippy/test to nix flake check via crane
status: todo
type: task
priority: normal
created_at: 2026-05-24T15:18:14Z
updated_at: 2026-05-24T15:23:37Z
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

- [ ] Add `crane` input to `flake.nix` (`inputs.crane.url = "github:ipetkov/crane"`, follow `nixpkgs`)
- [ ] Plumb `crane` through the overlay/lib so `craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain` is available alongside the existing `rustToolchain`
- [ ] Define a shared `src = craneLib.cleanCargoSource ./.` (or `./crates`, whichever scopes correctly) and `cargoArtifacts = craneLib.buildDepsOnly { inherit src; }`
- [ ] Rewrite `packages/beans-daemon/default.nix` to use `craneLib.buildPackage { inherit src cargoArtifacts; }` — preserve `pname`, `version`, any runtime deps / patches
- [ ] Add `checks.<system>.beans-daemon-fmt = craneLib.cargoFmt { inherit src; }`
- [ ] Add `checks.<system>.beans-daemon-clippy = craneLib.cargoClippy { inherit src cargoArtifacts; cargoClippyExtraArgs = "--workspace --all-targets -- -D warnings"; }`
- [ ] Add `checks.<system>.beans-daemon-test = craneLib.cargoNextest { inherit src cargoArtifacts; }` (fall back to `cargoTest` if nextest isn't desired)
- [ ] Update `flake.nix:185` so `checks` merges `self.packages` with the new crane checks (don't double-build the package)
- [ ] Verify locally: `nix flake check --print-build-logs` is green; all three new checks appear in `nix flake show`
- [ ] Update `crates/CLAUDE.md` Commands section to note that fmt/clippy/test are now part of `nix flake check`; refresh freshness date
- [ ] Open PR; confirm CI green

## Out of Scope

- Introducing `[workspace.lints]` or `clippy.toml` (per `crates/CLAUDE.md`: raise with user first). Clippy uses defaults + `-D warnings` only.
- A separate `cargo` GitHub Actions job — `nix flake check` is the single source of truth.
- Cross-platform CI matrix (macOS); `ubuntu-latest` stays. Pinned toolchain keeps results deterministic across platforms locally.
