# Spec: Relocate Rust build/check wiring into `crates/default.nix`

**Bean:** dotfiles-oqxj (parent epic: dotfiles-ubfq, Rust build improvements)
**Date:** 2026-06-06

## Goal

`flake.nix` should read as Rust-agnostic system/host wiring. Move all crate-build detail
(toolchain split, crane, `commonArgs`, `cargoArtifacts`, the fmt/clippy/test checks) into a
colocated module at `crates/default.nix`, exported as a second overlay fragment. The
`beans-daemon` package collapses to a call over a `buildLocalRustBin` helper.

This is a **relocation refactor**. The flake *outputs* are identical before and after (same
package binaries, same checks, same devShell). The one intentional build-invocation change is
scoping the `beans-daemon` package build from `--workspace` to `--bin beansd --bin beansctl`
— output-equivalent (both binaries still produced) but a real change in what cargo compiles
for the package. The fmt/clippy/test checks stay `--workspace`, and `cargoArtifacts` is still
built `--workspace` (a valid superset). No change to the daemon's runtime behavior.

## Background: current state (master)

All Rust wiring lives inside `dotfilesOverlay` in `flake.nix`:

- `rustyPkgs = prev.appendOverlays [ inputs.rust-overlay.overlays.default ]` (uses `prev` to
  avoid leaking `rust-bin.*` and to avoid `final` recursion).
- `buildToolchain` — bare `rust-bin.stable.latest.default` (rustc/cargo/clippy/rustfmt).
- `rustToolchain` — `buildToolchain.override { extensions = [ "rust-src" "rust-analyzer" ]; }`
  (devShell only).
- `craneLib = (inputs.crane.mkLib final).overrideToolchain buildToolchain`.
- `commonArgs = { src = <fileset Cargo.toml+Cargo.lock+crates>; strictDeps = true;
  cargoExtraArgs = "--locked --workspace"; buildInputs = lib.optionals stdenv.isDarwin [ libiconv ]; }`.
- `cargoArtifacts = craneLib.buildDepsOnly commonArgs`.
- `packageArgs.beans-daemon = { inherit craneLib commonArgs cargoArtifacts; }` — fed into the
  auto-discovered package via `discoverPackages ./packages` + `final.callPackage`.
- `rustChecks = { rust-fmt = craneLib.cargoFmt {...}; rust-clippy = craneLib.cargoClippy {...};
  rust-test = craneLib.cargoNextest {...}; }`.
- Exposed as `dotfiles.internal.{ rustToolchain, rustChecks }`.

`packages/beans-daemon/default.nix` is currently
`{ lib, craneLib, commonArgs, cargoArtifacts }: craneLib.buildPackage (commonArgs // { pname; version; ... doCheck = false; meta; })`.

Consumers in `flake.nix` outputs:
- `devShells` → `pkgs.dotfiles.internal.rustToolchain` + `RUST_SRC_PATH`.
- `packages.<sys>` → `mkPackages pkgs = removeAttrs pkgs.dotfiles [ "internal" ]`.
- `checks.<sys>` → `self.packages.<sys> // pkgs.dotfiles.internal.rustChecks`.

`packages/` has 5 discovered packages; only `beans-daemon` is Rust. The other four (`beans`,
`codex`, `cship`, `plannotator`) are non-Rust and must remain untouched.

## Design

### 1. New module: `crates/default.nix` (overlay fragment)

A function of `{ inputs }` returning an overlay (`final: prev: { ... }`):

```nix
{ inputs }:
final: prev:
let
  rustyPkgs = prev.appendOverlays [ inputs.rust-overlay.overlays.default ];

  buildToolchain = rustyPkgs.rust-bin.stable.latest.default;
  rustToolchain = buildToolchain.override {
    extensions = [ "rust-src" "rust-analyzer" ];
  };

  craneLib = (inputs.crane.mkLib final).overrideToolchain buildToolchain;

  commonArgs = {
    src = final.lib.fileset.toSource {
      root = ../.;                       # repo root, relative to crates/default.nix
      fileset = final.lib.fileset.unions [
        ../Cargo.toml
        ../Cargo.lock
        ../crates
      ];
    };
    strictDeps = true;
    cargoExtraArgs = "--locked --workspace";
    buildInputs = final.lib.optionals final.stdenv.isDarwin [ final.libiconv ];
  };
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  rustChecks = {
    rust-fmt = craneLib.cargoFmt { inherit (commonArgs) src; };
    rust-clippy = craneLib.cargoClippy (
      commonArgs // { inherit cargoArtifacts; cargoClippyExtraArgs = "--all-targets -- -D warnings"; }
    );
    rust-test = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });
  };
in
{
  # Builder helper: build the named local workspace bins as one package. The
  # package build is scoped to those bins (`--bin <name>` each); fmt/clippy/test
  # stay `--workspace` via commonArgs. Caller provides pname/version (these crates
  # are never released, so version is a cosmetic default).
  buildLocalRustBin =
    { pname, bins, version ? "0.1.0", meta ? { }, ... }@args:
    craneLib.buildPackage (
      commonArgs
      # Forward only EXTRA crane args; pname/version/meta/bins are handled
      # explicitly below so the `version` default actually takes effect (a
      # defaulted arg is not present in `args`).
      // (removeAttrs args [ "pname" "bins" "version" "meta" ])
      // {
        inherit pname version cargoArtifacts;
        cargoExtraArgs = "--locked " + final.lib.concatMapStringsSep " " (b: "--bin ${b}") bins;
        doCheck = false;
        meta = { mainProgram = final.lib.head bins; license = final.lib.licenses.mit; } // meta;
      }
    );

  # Extend (not clobber) dotfiles.internal with the Rust output plumbing.
  dotfiles = (prev.dotfiles or { }) // {
    internal = (prev.dotfiles.internal or { }) // { inherit rustToolchain rustChecks; };
  };
}
```

Notes:
- Path literals (`../Cargo.toml`, etc.) are resolved relative to `crates/default.nix`, i.e.
  repo root — equivalent to today's `./Cargo.toml` in `flake.nix`.
- `removeAttrs args [ "bins" "meta" ]` forwards `pname`/`version`/any extra crane args
  through, while `bins`/`meta` are handled explicitly (so they aren't passed twice).
- `version` defaults to `"0.1.0"`; callers may still pass it explicitly.

### 2. `flake.nix` changes

- **Delete** the entire Rust `let`-block from `dotfilesOverlay` (`buildToolchain`,
  `rustToolchain`, `craneLib`, `commonArgs`, `cargoArtifacts`, `packageArgs`, `rustChecks`)
  and the `internal = { inherit rustToolchain rustChecks; }` it produced.
- `dotfilesOverlay` shrinks to the discovery + merge only:
  ```nix
  dotfilesOverlay = final: prev: {
    dotfiles = (prev.dotfiles or { }) // (
      builtins.mapAttrs (name: path: final.callPackage path { }) packagePaths
    );
  };
  ```
  (No more `packageArgs`; `callPackage` auto-fills `buildLocalRustBin` for `beans-daemon`
  because it is a top-level `pkgs` attr, and `callPackage`'s built-in `intersectAttrs`
  passes it *only* to packages that declare it — the other four are unaffected.)
- Append the crates overlay to `defaultOverlays`:
  ```nix
  defaultOverlays = [
    inputs.alacritty-themes.overlays.default
    inputs.claude-code.overlays.default
    inputs.sprites-cli.overlays.default
    dotfilesOverlay
    (import ./crates { inherit inputs; })
  ];
  ```
- **Order-independence:** the two fragments own disjoint keys under `dotfiles` (discovery
  writes package-name keys; crates writes `dotfiles.internal`) and each merges
  `prev.dotfiles or { }`, so neither clobbers the other regardless of list order. `beans-daemon`
  resolves `buildLocalRustBin` from `final`, so it is present no matter the order.
- `devShells`, `packages`, `checks`, `mkPackages` output blocks are **unchanged**.

### 3. `packages/beans-daemon/default.nix`

Collapses to:

```nix
{ buildLocalRustBin }:
buildLocalRustBin {
  pname = "beans-daemon";
  version = "0.1.0";
  bins = [ "beansd" "beansctl" ];
  meta.description = "Background daemon (beansd) and control CLI (beansctl) for the beans issue tracker";
}
```

### 4. `crates/CLAUDE.md`

Add a short note that the workspace's Nix build/check wiring lives in `crates/default.nix`
(exporting `buildLocalRustBin` + the `rust-*` checks via an overlay), and bump the freshness
date. Keep the existing Commands section accurate (the four checks already documented there
do not change).

## Validation / acceptance

Run on aarch64-darwin locally; CI covers x86_64-linux.

1. `nix flake check` is green.
2. `nix flake show` still lists `packages.<sys>.beans-daemon` (+ `beans`, `codex`, `cship`,
   `plannotator`) and `checks.<sys>.{ rust-fmt, rust-clippy, rust-test }`.
3. `beans-daemon` closure is still ~51 MiB and `nix-store -q --references` shows `libiconv`
   only (no `rust-*` toolchain) — confirms `buildLocalRustBin` still pins `buildToolchain`.
4. Both `beansd` and `beansctl` are present in `$out/bin` — guards the `--bin` scoping change.
5. devShell still exposes a valid `RUST_SRC_PATH` and `rust-analyzer` on `PATH`.
6. `flake.nix` contains no `crane`/`craneLib`/`commonArgs`/`cargoArtifacts`/toolchain
   references (only the opaque `dotfiles.internal.{rustToolchain,rustChecks}` reads in the
   devShell/checks output blocks remain).

## Risks

- **`--bin` scoping:** relies on `beansd`/`beansctl` being unique bin names across the
  workspace (they are). Check (4) catches any regression.
- **Overlay merge:** the disjoint-key merge is caught at eval time if wrong; fallback is an
  explicit overlay order + `lib.recursiveUpdate`.
- **`crateNameFromCargoToml` not used:** version is caller-provided/defaulted, sidestepping
  workspace-inherited-version detection issues.

## Out of scope

- Behavioral changes beyond the deliberate `--bin` package scoping noted above (no toolchain
  bump, no check-flag changes, no `clippy.toml`/`[workspace.lints]`).
- Dependency caching on CI (separate future bean).
- Touching the other four discovered packages.
- Generalizing `buildLocalRustBin` beyond what `beans-daemon` needs (no second Rust package
  exists yet).
