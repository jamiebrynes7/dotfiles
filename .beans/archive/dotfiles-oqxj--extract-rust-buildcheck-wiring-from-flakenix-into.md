---
# dotfiles-oqxj
title: Extract Rust build/check wiring from flake.nix into crates/
status: completed
type: task
priority: normal
created_at: 2026-06-06T20:22:03Z
updated_at: 2026-06-06T21:10:50Z
parent: dotfiles-ubfq
---

Relocate all Rust build/check wiring out of `flake.nix`'s `dotfilesOverlay` into a colocated
`crates/default.nix`, exported as a second overlay fragment that provides a `buildLocalRustBin`
helper. `flake.nix` ends up Rust-agnostic.

**Spec (approved):** `docs/specs/2026-06-06-relocate-rust-wiring.md` — read it first; all design
decisions (caller-provided `pname`/`version`, `--bin` package scoping, disjoint-key overlay
merge) are locked there.

This is one atomic refactor: `flake.nix` will not evaluate until `crates/default.nix` exists
and `packages/beans-daemon/default.nix` matches `buildLocalRustBin`. Do all edits, then verify
as a unit — there is no meaningful intermediate green state to commit between files.

**Files:**
- Create: `crates/default.nix`
- Modify: `flake.nix` (overlay `let`-block ~L59-134, and `defaultOverlays` ~L136-141)
- Modify: `packages/beans-daemon/default.nix` (full rewrite)
- Modify: `crates/CLAUDE.md` (add a note + bump freshness)

---

- [x] **Step 1: Create `crates/default.nix`**

Move the Rust machinery here verbatim from `flake.nix`, wrapped as an overlay fragment. Note
path literals are now relative to `crates/` so they use `../` for repo-root files.

```nix
{ inputs }:
final: prev:
let
  # rust-overlay applied to `prev` so `rust-bin.*` doesn't leak into consumer
  # pkgs and to avoid `final` recursion.
  rustyPkgs = prev.appendOverlays [ inputs.rust-overlay.overlays.default ];

  # Bare `default` profile (rustc, cargo, clippy, rustfmt) used to build packages.
  # The `rust-src` extension lays down a `lib/rustlib/src/rust/library` tree in the
  # toolchain store path; compiled binaries embed those source paths
  # (panic/debuginfo metadata), so Nix's scanner records the whole toolchain as a
  # runtime dep. Excluding `rust-src` here removes the only such reference, keeping
  # it out of the package's runtime closure.
  buildToolchain = rustyPkgs.rust-bin.stable.latest.default;
  # devShell toolchain: build toolchain plus dev-only extensions.
  rustToolchain = buildToolchain.override {
    extensions = [
      "rust-src"
      "rust-analyzer"
    ];
  };

  # crane, pinned to the bare `buildToolchain` (not the fat devShell `rustToolchain`)
  # so dev-only extensions stay out of the package closure. `rustfmt` and `clippy`
  # are in the `default` profile, so the fmt/clippy checks work without extra
  # components.
  craneLib = (inputs.crane.mkLib final).overrideToolchain buildToolchain;

  # Args shared by the package build, its dependency-only artifact cache, and the
  # clippy/test checks — so cargo deps compile once and every derivation reuses the
  # same `cargoArtifacts`.
  commonArgs = {
    # Full workspace tree, not `cleanCargoSource`: `beansd` embeds non-Rust assets
    # (askama `.html` templates compiled by the derive macro, plus `.css`/`.js`
    # static files) that the cargo-only filter would strip. `buildDepsOnly` keys
    # its cache off Cargo.{toml,lock} only, so including assets here doesn't churn
    # the artifact cache.
    src = final.lib.fileset.toSource {
      root = ../.;
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

  # Workspace-wide Rust lint/test gates surfaced as flake checks. Named `rust-*`
  # (not `beans-daemon-*`) because `--workspace` means they cover every crate, not
  # just the shipped package.
  rustChecks = {
    rust-fmt = craneLib.cargoFmt { inherit (commonArgs) src; };
    rust-clippy = craneLib.cargoClippy (
      commonArgs
      // {
        inherit cargoArtifacts;
        cargoClippyExtraArgs = "--all-targets -- -D warnings";
      }
    );
    rust-test = craneLib.cargoNextest (commonArgs // { inherit cargoArtifacts; });
  };
in
{
  # Build the named local workspace bins as one package. The package build is
  # scoped to those bins (`--bin <name>` each); fmt/clippy/test stay `--workspace`
  # via commonArgs, and cargoArtifacts (built `--workspace`) is a valid superset.
  # Caller provides pname/version (these crates are never released, so version is
  # a cosmetic default).
  buildLocalRustBin =
    {
      pname,
      bins,
      version ? "0.1.0",
      meta ? { },
      ...
    }@args:
    craneLib.buildPackage (
      commonArgs
      # Forward only EXTRA crane args; pname/version/meta/bins are handled
      # explicitly below so the `version` default actually takes effect (a
      # defaulted arg is not present in `args`).
      // (removeAttrs args [
        "pname"
        "bins"
        "version"
        "meta"
      ])
      // {
        inherit pname version cargoArtifacts;
        cargoExtraArgs = "--locked " + final.lib.concatMapStringsSep " " (b: "--bin ${b}") bins;
        doCheck = false;
        meta = {
          mainProgram = final.lib.head bins;
          license = final.lib.licenses.mit;
        } // meta;
      }
    );

  # Extend (not clobber) dotfiles.internal with the Rust output plumbing the
  # devShell + checks read.
  dotfiles = (prev.dotfiles or { }) // {
    internal = (prev.dotfiles.internal or { }) // { inherit rustToolchain rustChecks; };
  };
}
```

- [x] **Step 2: Slim `dotfilesOverlay` in `flake.nix`**

Replace the entire Rust `let`-block + `in { dotfiles = ... internal = {...}; }` (current
~L59-134) with a discovery-only overlay. Delete `buildToolchain`/`rustToolchain`/`craneLib`/
`commonArgs`/`cargoArtifacts`/`packageArgs`/`rustChecks` from `flake.nix`.

```nix
      dotfilesOverlay = final: prev: {
        dotfiles = (prev.dotfiles or { }) // (
          builtins.mapAttrs (_name: path: final.callPackage path { }) packagePaths
        );
      };
```

(`callPackage` auto-fills `buildLocalRustBin` for `beans-daemon` because it is a top-level
`pkgs` attr; its built-in `intersectAttrs` passes it only to packages that declare it, so the
other four discovered packages are untouched and need no `packageArgs`.)

- [x] **Step 3: Append the crates overlay to `defaultOverlays`**

```nix
      defaultOverlays = [
        inputs.alacritty-themes.overlays.default
        inputs.claude-code.overlays.default
        inputs.sprites-cli.overlays.default
        dotfilesOverlay
        (import ./crates { inherit inputs; })
      ];
```

Leave `devShells`, `packages`, `checks`, and `mkPackages` exactly as they are — they still read
`pkgs.dotfiles.internal.rustToolchain`, `pkgs.dotfiles.internal.rustChecks`, and
`pkgs.dotfiles.<pkg>`.

- [x] **Step 4: Rewrite `packages/beans-daemon/default.nix`**

```nix
{ buildLocalRustBin }:
buildLocalRustBin {
  pname = "beans-daemon";
  version = "0.1.0";
  bins = [
    "beansd"
    "beansctl"
  ];
  meta.description = "Background daemon (beansd) and control CLI (beansctl) for the beans issue tracker";
}
```

- [x] **Step 5: Format the Nix files**

Run: `nixfmt flake.nix crates/default.nix packages/beans-daemon/default.nix`
Expected: no errors (parses clean).

- [x] **Step 6: Verify `nix flake check` is green**

Run: `nix flake check --print-build-logs`
Expected: green. The `beans-daemon` package + `rust-fmt`/`rust-clippy`/`rust-test` checks all
build/pass. (On aarch64-darwin locally; CI covers x86_64-linux.)

- [x] **Step 7: Verify outputs unchanged in `nix flake show`**

Run: `nix flake show`
Expected: `packages.<sys>` still lists `beans-daemon`, `beans`, `codex`, `cship`, `plannotator`;
`checks.<sys>` still lists `rust-fmt`, `rust-clippy`, `rust-test` (+ the packages).

- [x] **Step 8: Verify closure unchanged + both binaries present**

```bash
OUT=$(nix build .#beans-daemon --no-link --print-out-paths)
nix path-info -Sh "$OUT"                      # expect ~51 MiB
nix-store -q --references "$OUT"              # expect libiconv ONLY (no rust-* toolchain)
ls "$OUT/bin"                                 # expect both: beansd  beansctl
```
Expected: closure ~51 MiB, single `libiconv` reference, both `beansd` and `beansctl` in
`$out/bin`. (The references check proves `buildLocalRustBin` still pins the bare
`buildToolchain`; the `ls` proves the `--bin` scoping built both binaries.)

- [x] **Step 9: Verify devShell unaffected**

```bash
RTPATH=$(nix eval --raw .#devShells.aarch64-darwin.default.RUST_SRC_PATH)
test -d "$RTPATH" && echo "rust-src OK"
```
Expected: `RUST_SRC_PATH` resolves to an existing dir (devShell still gets the fat
`rustToolchain`).

- [x] **Step 10: Confirm `flake.nix` is Rust-agnostic**

Run: `grep -nE 'crane|craneLib|commonArgs|cargoArtifacts|buildToolchain|rustPlatform' flake.nix`
Expected: no matches. (Only `dotfiles.internal.rustToolchain` / `internal.rustChecks` opaque
reads remain in the devShell/checks output blocks — those are output plumbing, acceptable.)

- [x] **Step 11: Update `crates/CLAUDE.md`**

Add a short note (near Purpose/Boundaries) that the workspace's Nix build + check wiring lives
in `crates/default.nix` — an overlay fragment exporting `buildLocalRustBin` (used by
`packages/beans-daemon/default.nix`) and the `rust-*` checks. Bump the `Freshness:` date to the
day of implementation. Do not change the documented check names (they are unchanged).

- [x] **Step 12: Commit**

```bash
git add flake.nix crates/default.nix packages/beans-daemon/default.nix crates/CLAUDE.md .beans/
git commit -m "crates: relocate Rust build/check wiring into crates/default.nix

Move the toolchain split, crane lib, commonArgs, cargoArtifacts, and the
rust-* checks out of flake.nix's overlay into a colocated crates/default.nix
overlay fragment exporting a buildLocalRustBin helper. flake.nix is now
Rust-agnostic. Pure relocation; the only build-invocation change is scoping
the package to --bin beansd --bin beansctl (output-equivalent).

Bean: dotfiles-oqxj"
```

---

## Acceptance

- `nix flake check` green (darwin local + linux CI).
- `nix flake show` outputs unchanged (5 packages, 3 `rust-*` checks).
- `beans-daemon` closure ~51 MiB, `libiconv`-only runtime ref; both binaries installed.
- devShell `RUST_SRC_PATH` valid.
- `flake.nix` has no crane/toolchain build references.

## Notes / fallback

- If the disjoint-key overlay merge misbehaves at eval, fall back to a fixed overlay order with
  `lib.recursiveUpdate` for `dotfiles`.
- If relocation proves uglier than it's worth (e.g. `final`/`prev` plumbing), it is acceptable
  to scrap with a recorded rationale per the original bean.

## Summary of Changes

Relocated all Rust build/check wiring out of `flake.nix` into a new `crates/default.nix` overlay fragment. `flake.nix` is now Rust-build-agnostic (only the `crane` *input* declaration remains, which must live there).

- **New `crates/default.nix`** (`{ inputs }: final: prev: { ... }`): holds the toolchain split (`buildToolchain`/`rustToolchain`), `craneLib`, `commonArgs`, `cargoArtifacts`, and the `rust-*` checks. Exports `buildLocalRustBin { pname, bins, version ? "0.1.0", meta ? {}, ... }` (scopes the package build to `--bin <name>` per bin; checks stay `--workspace`) and `dotfiles.internal.{rustToolchain,rustChecks}`.
- **`flake.nix`**: `dotfilesOverlay` slimmed to discovery only; `(import ./crates { inherit inputs; })` appended to `defaultOverlays`. `devShells`/`packages`/`checks` output blocks unchanged.
- **`packages/beans-daemon/default.nix`**: collapsed to `{ buildLocalRustBin }: buildLocalRustBin { pname; version; bins = [ "beansd" "beansctl" ]; meta.description; }`.
- **`crates/CLAUDE.md`**: documents `crates/default.nix` as the build/check home; Commands + Boundaries updated for `--bin` scoping.
- **Spec**: `docs/specs/2026-06-06-relocate-rust-wiring.md`.

### Deviation from spec
The spec's order-independent disjoint-key overlay merge didn't survive: **nixpkgs already has a `dotfiles` attribute** (a Python tool), so `(prev.dotfiles or {})` in the discovery overlay inherited that derivation's attrs (surfaced as `packages.<sys>.outPath is not a derivation`). Fixed by having `dotfilesOverlay` do a **plain assignment** (deliberately shadowing nixpkgs' `dotfiles`, as the original code did), with only the `crates` overlay merging `prev.dotfiles`. This makes the `dotfilesOverlay`-then-`crates` order **required** — guaranteed by `defaultOverlays` list position.

### Verified (aarch64-darwin; linux via eval + CI)
- `nix flake check` green (89 tests via nextest, clippy/fmt pass).
- `nix flake show`: 5 packages + `rust-fmt`/`rust-clippy`/`rust-test`.
- `beans-daemon` closure 51.4 MiB, runtime ref `libiconv` only; both `beansd` + `beansctl` installed.
- devShell `RUST_SRC_PATH` valid.
- Subagent review: 1 Required (stale `--workspace` doc line) fixed; overlay-header comment added. User review: no changes.
