---
# dotfiles-g2br
title: Add Rust toolchain to flake devShell
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:55:43Z
updated_at: 2026-05-09T13:21:19Z
parent: dotfiles-m592
---

**Files:**
- Modify: `flake.nix`

Pin a single Rust toolchain via [`oxalica/rust-overlay`](https://github.com/oxalica/rust-overlay) and use it for **both** this repo's devShell and the `beans-daemon` package build, so `nix develop` and `nix build` never disagree on cargo/rustc versions.

Two design constraints:

- **No toolchain divergence.** A single `mkRustToolchain` helper is the source of truth. The devShell consumes it directly; `mkPackages` constructs a matching `rustPlatform` from it and overrides `beans-daemon`'s `rustPlatform` callPackage arg. F9's `packages/beans-daemon/default.nix` already accepts `rustPlatform` — no source change there.
- **No leak into downstream consumers.** The `lib.mkShells` helper stays the way downstream system configs invoke it (`mkShells { }` keeps producing a Rust-free shell). Rust shows up only because **this** flake's `devShells = mkShells { extraPackages = ...; extraEnv = ...; };` call passes the toolchain in. To make that possible, `mkShells` gains two new parameters.

The devShell tools (rust-analyzer, etc.) are purely for ergonomic interactive iteration; the package build itself happens via `rustPlatform.buildRustPackage` regardless.

- [x] **Step 1: Add `rust-overlay` to flake inputs**

In `flake.nix`'s `inputs = { ... }` block (alongside `alacritty-themes`, `claude-code`, etc.):
```nix
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [x] ~~**Step 2: Wire the overlay into `defaultOverlays`**~~ (superseded — overlay applied locally inside `dotfilesOverlay` only; see Summary of Changes)

In the `let` body of `outputs`, append to `defaultOverlays`:
```nix
      defaultOverlays = [
        inputs.alacritty-themes.overlays.default
        inputs.claude-code.overlays.default
        inputs.sprites-cli.overlays.default
        inputs.rust-overlay.overlays.default
      ];
```

After this, `pkgs.rust-bin.*` is available wherever `nixOsPkgs` / `nixDarwinPkgs` is used.

- [x] ~~**Step 3: Add the toolchain helper (single source of truth)**~~ (superseded — toolchain construction lives inside `dotfilesOverlay`; see Summary of Changes)

In the `let` body of `outputs` (e.g. just above `discoverPackages` around line 132):
```nix
      mkRustToolchain = pkgs:
        pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };
```

Notes:
- `latest` is locked by `flake.lock` — every checkout pins the same Rust version until `nix flake update rust-overlay`. Swap for `pkgs.rust-bin.stable."1.83.0".default` to pin a specific release independent of rust-overlay's `latest` pointer.
- `rust-src` is what makes `RUST_SRC_PATH` resolvable. `rust-analyzer` ships a matching analyzer build.

- [x] **Step 4: Extend `mkShells` to accept per-system packages and env**

The current signature only accepts a flat list of `extraPackages`, which can't express "construct a derivation from this system's pkgs" (needed for the toolchain). Replace `mkShells` (around line 123):
```nix
      mkShells = { extraPackages ? [ ] }: {
        aarch64-darwin.default =
          let pkgs = nixDarwinPkgs { };
          in pkgs.mkShell { packages = baseShellPkgs pkgs ++ extraPackages; };
        x86_64-linux.default =
          let pkgs = nixOsPkgs { system = "x86_64-linux"; };
          in pkgs.mkShell { packages = baseShellPkgs pkgs ++ extraPackages; };
      };
```
with:
```nix
      mkShells = { extraPackages ? (_: [ ]), extraEnv ? (_: { }) }:
        let
          mkOne = pkgs:
            pkgs.mkShell ({
              packages = baseShellPkgs pkgs ++ extraPackages pkgs;
            } // extraEnv pkgs);
        in {
          aarch64-darwin.default = mkOne (nixDarwinPkgs { });
          x86_64-linux.default   = mkOne (nixOsPkgs { system = "x86_64-linux"; });
        };
```

Behavioural notes:
- `extraPackages` is now a function `pkgs -> list`. Default `(_: [ ])` keeps `mkShells { }` (the downstream call shape) producing exactly the shell it produces today.
- `extraEnv` is a new function `pkgs -> attrset`. Whatever it returns is merged into the `mkShell` attrset, so each key becomes an env var in the dev shell (this is the standard nixpkgs `mkShell` convention for env passthrough).
- Existing callers passing `extraPackages = [ ... ]` (a flat list) need to migrate to `extraPackages = pkgs: [ ... ]`. There are no such callers in this repo today; downstream system-template callers should be checked.

- [x] **Step 5: This repo's `devShells` call gains the Rust extras**

Replace `devShells = mkShells { };` (around line 147) with:
```nix
      devShells = mkShells {
        extraPackages = pkgs: [ (mkRustToolchain pkgs) ];
        extraEnv = pkgs:
          let toolchain = mkRustToolchain pkgs; in
          { RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library"; };
      };
```

`mkRustToolchain` is invoked twice per system (once for packages, once for env), but both calls hit the same Nix store path — no extra build, no duplicate evaluation cost worth worrying about.

- [x] ~~**Step 6: Route the same toolchain into `mkPackages`**~~ (superseded — packages built directly inside `dotfilesOverlay`; see Summary of Changes)

Replace `mkPackages` (around line 142):
```nix
      mkPackages = pkgs:
        builtins.mapAttrs (_: path: pkgs.callPackage path { }) packagePaths;
```
with:
```nix
      mkPackages = pkgs:
        let
          toolchain    = mkRustToolchain pkgs;
          rustPlatform = pkgs.makeRustPlatform { cargo = toolchain; rustc = toolchain; };
          # Per-package overrides — extend as more packages need custom args.
          overrides    = {
            beans-daemon = { inherit rustPlatform; };
          };
        in
        builtins.mapAttrs
          (name: path: pkgs.callPackage path (overrides.${name} or { }))
          packagePaths;
```

The override only fires for `beans-daemon`. Other packages keep their existing default-args behaviour. F9's `packages/beans-daemon/default.nix` already accepts `rustPlatform` as an argument — no change needed there.

Net effect: `nix develop` and `nix build .#beans-daemon` both resolve to the same toolchain derivation in the Nix store.

- [x] **Step 7: Update the lockfile and verify**

```
nix flake update rust-overlay
nix develop -c cargo --version
nix develop -c rustc --version
nix develop -c rust-analyzer --version
nix develop -c sh -c 'echo "$RUST_SRC_PATH" && ls "$RUST_SRC_PATH"'
```
Expected: each `--version` prints a string from the same toolchain release. The `RUST_SRC_PATH` listing should show `core/`, `std/`, `alloc/`, etc.

Verify the package build picks up the same toolchain (only meaningful once F1.T1 has produced an actual crate; skip until then):
```
nix build .#beans-daemon -L 2>&1 | grep -E 'cargo|rustc' | head -20
```

- [x] **Step 8: `nix flake check` still passes**

Run: `nix flake check`
Expected: no evaluation errors. (Also a smoke check that no downstream caller of `mkShells` was accidentally broken by the signature change.)

- [x] **Step 9: Commit**

```
git add flake.nix flake.lock
git commit -m '.: add rust-overlay + share Rust toolchain between devShell and packages'
```

(Path prefix `.` because the change is at the flake root.)

## Summary of Changes

Pivoted from the original 9-step flake-edit plan to a single overlay-based design after a code-review round on the first implementation surfaced a "rust-overlay leaks into downstream consumers' pkgs" concern.

**What was actually built:**
- `dotfilesOverlay` constructs every package under `packages/` and exposes them at `pkgs.dotfiles.<name>`. `rust-overlay` is applied locally on `prev.appendOverlays` inside this overlay only — it is **not** added to `defaultOverlays`, so `rust-bin.*` does not leak into consumers' pkgs.
- The shared Rust toolchain lives at `pkgs.dotfiles.internal.rustToolchain`. `dotfilesRustPlatform` stays scoped to the overlay's `let` and is wired into `beans-daemon`'s callPackage args via a `packageArgs` map.
- `mkPackages` collapses to `pkgs: builtins.removeAttrs pkgs.dotfiles [ "internal" ]`.
- `mkShells` signature gains function-form `extraPackages` / `extraEnv` (needed to reach `pkgs` for the toolchain). Did **not** add the `overlays` param the spec implied.
- `mkRustToolchain` helper from the original plan was removed — toolchain construction lives entirely inside `dotfilesOverlay`.

**Files modified:**
- `flake.nix` — overlay restructure as above.
- `flake.lock` — `rust-overlay` added.
- `home/programs/beans.nix`, `home/programs/claude-code/cship/default.nix`, `home/programs/claude-code/plannotator/default.nix` — migrated from `pkgs.callPackage ../../packages/<name> { }` to inlined `pkgs.dotfiles.<name>`.

**Verified:**
- `cargo --version` / `rustc --version` / `rust-analyzer --version` all report 1.95.0 from the same toolchain store path.
- `RUST_SRC_PATH` resolves to a valid `rustlib/src/rust/library` tree.
- `nix flake check` passes; existing package `.drv` hashes unchanged — no surprise rebuilds for downstream.

**Follow-ups for `dotfiles-uzwl`:**
- `packages/beans-daemon/default.nix` should accept `rustPlatform` as a callPackage arg; the overlay's `packageArgs` already routes the pinned `rustPlatform` to it by name.
- `home/programs/beans-daemon.nix` (later, in `dotfiles-ottn`) should reference `pkgs.dotfiles.beans-daemon` directly, matching the new pattern.
