---
# dotfiles-d1qc
title: Slim beans-daemon closure by using a minimal build toolchain
status: todo
type: task
created_at: 2026-05-30T17:35:50Z
updated_at: 2026-05-30T17:35:50Z
parent: dotfiles-ubfq
---

The `beans-daemon` package retains a runtime reference to the full `rust-default` toolchain bundle, dragging its entire closure (rust-docs 634MB, rustc 369MB, rust-analyzer, clippy, rustfmt, rust-src, rust-std) into the result even though none of it is used at runtime.

## Root cause

`flake.nix:55-61` uses **one** toolchain for both the devShell and the build platform:

```nix
rustToolchain = rustyPkgs.rust-bin.stable.latest.default.override {
  extensions = [ "rust-src" "rust-analyzer" ];   # dev-shell concerns
};
rustPlatform = final.makeRustPlatform { cargo = rustToolchain; rustc = rustToolchain; };
```

The compiled binaries embed std-library source paths (`.../rust-default-1.95.0/lib/rustlib/src/rust/library/...`) via panic/`#[track_caller]`/debuginfo metadata. Nix's reference scanner sees the hash and records a hard runtime dep on the whole `rust-default` aggregate. `rust-src` and `rust-analyzer` are devShell-only but get pulled into the package closure because the build reuses the fat toolchain.

Verified: `nix-store -q --references result` shows exactly `rust-default-1.95.0` + `libiconv`; `strings bin/beansd | grep rust-default` shows thousands of embedded `lib/rustlib/src/rust/library/...` paths.

## Approach

Split the build toolchain from the dev toolchain. Build with the bare `default` profile (rustc + cargo + clippy + rustfmt, no `rust-src`/`rust-analyzer`); keep the fat one for the devShell only.

```nix
buildToolchain = rustyPkgs.rust-bin.stable.latest.default;
rustToolchain  = buildToolchain.override {
  extensions = [ "rust-src" "rust-analyzer" ];
};
rustPlatform = final.makeRustPlatform { cargo = buildToolchain; rustc = buildToolchain; };
```

This shrinks the retained closure (drops rust-docs ~634MB, rust-analyzer ~38MB, rust-src ~46MB). The package still references `buildToolchain` for std paths, but a far smaller bundle.

## Todos

- [ ] Add a `buildToolchain` (bare `default` profile) in the overlay at `flake.nix:55`; derive the devShell `rustToolchain` from it via `.override` with the `rust-src`/`rust-analyzer` extensions
- [ ] Point `makeRustPlatform` (`flake.nix:58-61`) at `buildToolchain`
- [ ] Confirm devShell still exposes `rust-src` (`flake.nix:175,178`) and `rust-analyzer`
- [ ] Rebuild and verify: `nix-store -q --references result` no longer pulls rust-docs / rust-analyzer / rust-src; capture before/after closure size with `nix path-info -Sh result`
- [ ] If the crane migration (dotfiles-u7oa) lands first, point `craneLib.overrideToolchain` at `buildToolchain` instead — coordinate so the two changes don't conflict

## Out of Scope

- Fully eliminating the toolchain reference (would require `--remap-path-prefix` on std paths or `removeReferencesTo` post-build) — only pursue if the smaller bundle is still too large.
