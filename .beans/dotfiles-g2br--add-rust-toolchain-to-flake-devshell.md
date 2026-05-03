---
# dotfiles-g2br
title: Add Rust toolchain to flake devShell
status: todo
type: task
priority: normal
created_at: 2026-05-03T14:55:43Z
updated_at: 2026-05-03T15:03:48Z
parent: dotfiles-m592
---

**Files:**
- Modify: `flake.nix`

Pin a single Rust toolchain via [`oxalica/rust-overlay`](https://github.com/oxalica/rust-overlay) and use it for **both** this repo's devShell and the `beans-daemon` package build. This avoids `nix develop` running one Rust version while `nix build` uses another.

Two things matter here:

- **No toolchain divergence.** `mkRustToolchain` is the single source of truth. The devShell consumes it directly; `mkPackages` constructs a matching `rustPlatform` from it and passes it to `beans-daemon` via callPackage override. F9's `packages/beans-daemon/default.nix` already takes `rustPlatform` as a function argument, so no change is needed there.
- **No leak into downstream consumers.** The exported `lib.mkShells` helper stays Rust-free. Downstream system configs that call `dotfiles.lib.mkShells { }` see no change. Rust + `RUST_SRC_PATH` live only in this flake's own `devShells` output.

The devShell tools (rust-analyzer, etc.) are purely for ergonomic interactive iteration; the package build itself happens via `rustPlatform.buildRustPackage` regardless.

- [ ] **Step 1: Add `rust-overlay` to flake inputs**

In `flake.nix`'s `inputs = { ... }` block (alongside `alacritty-themes`, `claude-code`, etc.):
```nix
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 2: Wire the overlay into `defaultOverlays`**

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

- [ ] **Step 3: Add the toolchain helper (single source of truth)**

In the `let` body of `outputs` (e.g. just above `discoverPackages` around line 132):
```nix
      mkRustToolchain = pkgs:
        pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };
```

Notes:
- `latest` here is locked by `flake.lock` — every checkout pins the same Rust version until `nix flake update rust-overlay`. Swap for `pkgs.rust-bin.stable."1.83.0".default` if you want to pin to a specific release independent of rust-overlay's `latest` pointer.
- `rust-src` is what makes `RUST_SRC_PATH` resolvable. `rust-analyzer` ships a matching analyzer build.

- [ ] **Step 4: Leave `mkShells` and `baseShellPkgs` unchanged**

Do NOT add Rust to `baseShellPkgs` or to the `mkShells` helper. Both stay as they are today — that keeps the exported `lib.mkShells` Rust-free for downstream consumers.

- [ ] **Step 5: Replace `devShells = mkShells { };` with an inline definition for this repo only**

In the outputs attrset (around line 147), replace:
```nix
      devShells = mkShells { };
```
with:
```nix
      devShells =
        let
          mkRustShell = pkgs:
            let toolchain = mkRustToolchain pkgs; in
            pkgs.mkShell {
              packages      = baseShellPkgs pkgs ++ [ toolchain ];
              RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
            };
        in {
          aarch64-darwin.default = mkRustShell (nixDarwinPkgs { });
          x86_64-linux.default   = mkRustShell (nixOsPkgs { system = "x86_64-linux"; });
        };
```

The repo's own devShells now bake in Rust and `RUST_SRC_PATH`; downstream consumers that call `dotfiles.lib.mkShells { }` are unaffected.

- [ ] **Step 6: Route the same toolchain into `mkPackages`**

Replace the existing `mkPackages` (around line 142):
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

The override only fires for `beans-daemon`. All other packages still get the default `pkgs.callPackage path { }` behaviour. F9's `packages/beans-daemon/default.nix` already accepts `rustPlatform` as an argument — no change needed there.

Net effect: `nix develop` and `nix build .#beans-daemon` both resolve to the same toolchain derivation in the Nix store.

- [ ] **Step 7: Update the lockfile and verify**

```
nix flake update rust-overlay
nix develop -c cargo --version
nix develop -c rustc --version
nix develop -c rust-analyzer --version
nix develop -c sh -c 'echo "$RUST_SRC_PATH" && ls "$RUST_SRC_PATH"'
```
Expected: each `--version` prints a string from the same toolchain release. The `RUST_SRC_PATH` listing should show `core/`, `std/`, `alloc/`, etc.

Then verify the package build picks up the same toolchain (cargo version inside the build sandbox should match what `nix develop` reports):
```
nix build .#beans-daemon -L 2>&1 | grep -E 'cargo|rustc' | head -20
```
(Only meaningful once F1.T1 has produced an actual crate to build. Skip until then.)

- [ ] **Step 8: `nix flake check` still passes**

Run: `nix flake check`
Expected: no evaluation errors.

- [ ] **Step 9: Commit**

```
git add flake.nix flake.lock
git commit -m '.: add rust-overlay; share toolchain between devShell and packages'
```

(Path prefix `.` because the change is at the flake root.)
