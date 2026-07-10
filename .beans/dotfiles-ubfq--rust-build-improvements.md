---
# dotfiles-ubfq
title: Rust build improvements
status: completed
type: epic
priority: normal
created_at: 2026-05-30T17:35:24Z
updated_at: 2026-07-04T21:03:43Z
order: c
---

Thematic container for improvements to how the Rust workspace (`crates/`) is built and gated under Nix.

Two related threads:

1. **CI lint/build/test loop** — make `nix flake check` cover fmt → clippy → test, not just the package build. Tracked by the crane-migration child.
2. **Closure slimming** — the `beans-daemon` package retains a runtime reference to the full `rust-default` toolchain bundle (rustc, rust-docs, rust-analyzer, clippy, rust-src), bloating its closure by ~750MB+ of artifacts that aren't used at runtime. Tracked by the toolchain-slimming child.

## Background: why the closure is bloated

`result` → `beans-daemon-0.1.0` has exactly two direct runtime references: `rust-default-1.95.0` and `libiconv`. The `rust-default` aggregate is rust-overlay's `default` profile **plus the `rust-src` and `rust-analyzer` extensions** (`flake.nix:55-57`), all symlinked into one store path; its closure pulls in rust-docs (634MB), rustc (369MB), rust-std, rust-analyzer, clippy, rustfmt, rust-src.

The reference is embedded because the compiled binaries contain std-library **source paths** (panic / `#[track_caller]` / debuginfo `file!()` metadata) of the form `.../rust-default-1.95.0/lib/rustlib/src/rust/library/...`. That directory only exists because the toolchain carries the `rust-src` extension. Nix's reference scanner sees the hash and records a hard runtime dep on the whole bundle.

The build platform (`makeRustPlatform` at `flake.nix:58-61`) reuses the same fat toolchain as the devShell, so dev-only components (`rust-src`, `rust-analyzer`) leak into the package's runtime closure.

## Relationship between the two children

The threads are **orthogonal**: crane vs `buildRustPackage` does not change the embedded std-source paths, so the crane migration alone would not slim the closure. But the migration is a natural moment to also point `overrideToolchain` at a minimal `default`-profile toolchain, fixing both at once.
