---
# dotfiles-rdkr
title: Add overlays/paseo.nix exposing pkgs.dotfiles.paseo
status: completed
type: task
priority: normal
created_at: 2026-08-19T10:55:26Z
updated_at: 2026-08-19T14:15:32Z
parent: dotfiles-pg0j
blocked_by:
    - dotfiles-l710
---

**Files:**
- Create: `overlays/paseo.nix` (new top-level `overlays/` directory)
- Modify: `flake.nix` — the `defaultOverlays` list

Context: upstream's `nix/package.nix` exposes `npmDepsHash` as a **function argument** precisely so downstream flakes on a different nixpkgs can supply their own. `buildNpmPackage` destructures it, so `overrideAttrs` cannot reach it — `callPackage` with an explicit argument is the supported route, and is cleaner than the `npmDeps.overrideAttrs` hack in `sys-warbird`.

The overlay must be appended **after** `dotfilesOverlay` in `defaultOverlays`, because that one plain-assigns `dotfiles` and would otherwise clobber this. Extending with `(prev.dotfiles or { }) // { ... }` matches `crates/default.nix`.

- [x] **Step 1: Create `overlays/paseo.nix` with a placeholder hash**

```nix
# A nixpkgs overlay fragment (not a buildable package) exposing a patched paseo
# as `pkgs.dotfiles.paseo`. Upstream does not build as tagged, so two patches
# ride along. Re-verified against v0.3.1 and v0.4.0, whose `nix/package.nix`
# files are byte-identical -- neither patch is close to landing upstream.
{ inputs }:
final: prev:
let
  paseo =
    (final.callPackage "${inputs.paseo}/nix/package.nix" {
      # Every release tag ships a stale `nix/npm-deps.hash`. Two upstream
      # mechanics combine: `fetchNpmDeps` copies package-lock.json into its
      # fixed-output result, so the version-string churn in `chore(release): cut
      # X` moves the hash even when the dependency set is byte-identical; and
      # the workflow that repairs it triggers on push to main, landing ~10min
      # *after* the release commit is tagged. So the tag always points at the
      # pre-repair state (holds for v0.2.5, v0.3.0, v0.3.1).
      #
      # Expect to re-point this at every bump rather than to drop it: take the
      # `got:` hash from the failing build. Overriding is safe either way --
      # package-lock.json's integrity fields pin the fetched contents
      # independently of this hash.
      npmDepsHash = "sha256-oXz8hMk+5DlTYK8OndUAjB+RJMDbPqobVGXLFeoH++o=";
    }).overrideAttrs
      (old: {
        # scripts/trace-daemon.mjs walks the JS module graph, so node-pty's
        # prebuilt native binding never makes it into $out and every terminal
        # pane reports "Terminal worker not running". Same cp as upstream PR
        # #3250; drop this once that (or a real trace fix) lands in a release.
        postInstall = (old.postInstall or "") + ''
          mkdir -p "$out/lib/paseo/packages/server/node_modules/node-pty"
          cp -r packages/server/node_modules/node-pty/prebuilds \
            "$out/lib/paseo/packages/server/node_modules/node-pty/"
        '';
      });
in
{
  # Extend (not clobber) the set `dotfilesOverlay` assigns. This overlay must
  # come after it in `defaultOverlays`.
  dotfiles = (prev.dotfiles or { }) // { inherit paseo; };
}
```

The starting hash is `sys-warbird`'s current value. It was computed against paseo's own nixpkgs-unstable rather than this repo's nixpkgs 26.05, so it may well not match — Step 4 resolves the real one.

- [x] **Step 2: Wire it into `defaultOverlays`**

In `flake.nix`, append to the `defaultOverlays` list (after the `crates` entry):

```nix
      defaultOverlays = [
        inputs.alacritty-themes.overlays.default
        dotfilesOverlay
        (import ./crates { inherit inputs; })
        (import ./overlays/paseo.nix { inherit inputs; })
      ];
```

- [x] **Step 3: Verify the attribute exists (eval only, no build)**

Run: `nix eval --raw .#packages.aarch64-darwin.paseo.name`
Expected: `paseo-0.3.1`

If this errors with `attribute 'paseo' missing`, the overlay is ordered before `dotfilesOverlay` or the `dotfiles` merge is wrong.

- [x] **Step 4: Resolve the real `npmDepsHash`**

Run: `nix build .#packages.aarch64-darwin.paseo --no-link 2>&1 | tail -20`

Two possible outcomes:

- It builds. The starting hash was correct; go to Step 5.
- It fails with a hash mismatch:

  ```
  error: hash mismatch in fixed-output derivation '/nix/store/...-paseo-0.3.1-npm-deps.drv':
           specified: sha256-oXz8hMk+5DlTYK8OndUAjB+RJMDbPqobVGXLFeoH++o=
              got:    sha256-<actual>
  ```

  Copy the `got:` value into `npmDepsHash` in `overlays/paseo.nix` and re-run the build. This is the expected workflow at every bump, not a one-off.

- [x] **Step 5: Verify the node-pty patch landed**

Run: `ls $(nix build .#packages.aarch64-darwin.paseo --no-link --print-out-paths)/lib/paseo/packages/server/node_modules/node-pty/prebuilds`
Expected: a non-empty directory listing. An empty result or `No such file` means the `postInstall` did not apply.

- [x] **Step 6: Format check**

Run: `nixfmt --check flake.nix overlays/paseo.nix`
Expected: no output, exit 0.

- [x] **Step 7: Commit**

```bash
git add flake.nix overlays/paseo.nix
git commit -m "overlays: add patched paseo as pkgs.dotfiles.paseo

Bean: dotfiles-rdkr"
```

## Review triage (subagent, 2026-08-19)

Verdict was *Needs Discussion* — no blocking defects. Applied:

- **Documented what the hash must satisfy** (the deliverable `dotfiles-egs1` asked for):
  one hash serves both `inputs.nixpkgs` (linux) and `inputs.nixpkgs-darwin`, valid today
  only because both pins resolve `prefetch-npm-deps` to the identical source. Also warns
  that a `got:` hash taken on your own platform is not necessarily right for both.
- **Narrowed the prebuilds copy to the host triple.** The full tree is 24MB (≈21MB of it
  win32 debug symbols) to deliver ~140KB; the runtime loader keys strictly on
  `prebuilds/<platform>-<arch>`. Deviates from upstream PR #3250's whole-tree `cp` on
  purpose, and says so.
- **Added a guard that fails the build** if `$out/.../node-pty/prebuilds` already exists.
  Nothing else would ever tell us #3250 shipped, and a plain `cp` would silently nest a
  redundant `prebuilds/` inside upstream's.
- **Corrected two comment claims**: the hash churn is driven by upstream *rewriting
  package-lock.json* in its repair commit, not merely version-string churn; dropped the
  unsupported "~10min" window; dated the v0.4.0 byte-identical claim rather than asserting
  it open-endedly.
- **Documented the ordering contract where it is actually edited** (`flake.nix`'s
  `defaultOverlays`), because a misorder fails *silently*: an overlay placed before
  `dotfilesOverlay` is plain-assigned over, dropping its packages out of `packages.*` and
  `checks.*` with no eval error — which for paseo would disable the very stale-hash gate
  this design exists to provide. Also corrected the `dotfilesOverlay` docstring, which
  still claimed only `crates` extends the set.

Deferred (not defects in this diff): CI has no binary cache and the npm-deps FOD alone is
2.1GB with a 364MiB output closure, so every PR rebuilds paseo cold on `ubuntu-latest` —
a plausible ENOSPC that would present as an unrelated failure. The spec's claim that the
darwin build "stays evaluation-only" is also now wrong: `checks.aarch64-darwin.paseo` is a
real build.

## Deviations from the bean as written

- The bean omits that `overlays/paseo.nix` must be `git add`-ed before Nix can see it —
  the flake source is git-filtered, so Step 3 otherwise fails with
  `Path 'overlays/paseo.nix' ... is not tracked by Git`, which looks nothing like the
  `attribute 'paseo' missing` symptom the bean tells you to expect.
- Step 4's premise did not hold: the placeholder hash (`sys-warbird`'s value) built clean
  against this repo's `nixpkgs-darwin` 26.05, so no hash resolution was needed. Upstream's
  v0.3.1 sidecar (`sha256-RCp5Og...`) does *not* match, so the override is still required.

## Summary of Changes

Added `overlays/paseo.nix` (new top-level `overlays/` directory) exposing a patched paseo
at `pkgs.dotfiles.paseo`, and appended it to `defaultOverlays` in `flake.nix` after the
`crates` entry.

The overlay calls `final.callPackage "${inputs.paseo}/nix/package.nix"` with an explicit
`npmDepsHash` — the supported route, since `buildNpmPackage` destructures that argument so
`overrideAttrs` cannot reach it (upstream exposes it as a function argument for exactly
this reason). It then `overrideAttrs` a `postInstall` copying node-pty's prebuilt binding
into `$out`, which `scripts/trace-daemon.mjs` otherwise omits, breaking every terminal
pane.

Because `mkPackages = builtins.removeAttrs pkgs.dotfiles [ "internal" ]`, paseo now lands
in both `packages.*` and `checks.*` — which is the point: `nix flake check` is the only
thing that catches a stale `npmDepsHash` after a nixpkgs or paseo bump.

### Verified

- `nix eval --raw .#packages.{aarch64-darwin,x86_64-linux}.paseo.name` → `paseo-0.3.1`.
- `nix build .#packages.aarch64-darwin.paseo` succeeds; the placeholder hash
  (`sha256-oXz8hM...`, from `sys-warbird`) was already correct against this repo's
  `nixpkgs-darwin` 26.05, so no hash resolution was needed. Upstream's v0.3.1 sidecar
  (`sha256-RCp5Og...`) does not match, confirming the override is required.
- The patch lands `prebuilds/darwin-arm64/{pty.node,spawn-helper}` with the exec bit
  preserved, 140K instead of the whole 24MB tree; output closure 341MiB (was 364MiB).
- The upstream-shipped-prebuilds guard was exercised in isolation across all three cases
  (absent dir, no prebuilds, prebuilds present) — fires only in the last.
- `nixfmt --check` clean; `nix flake check` → **all checks passed**.

### Not verified locally

`nix flake check` reports `omitted these incompatible systems: x86_64-linux`, so the linux
build of paseo has *not* been built on this machine — only evaluated. CI's ubuntu runner
is what proves it. Evidence it should work: upstream's `autoPatchelfHook` skips
foreign-arch prebuilds, node-pty ships `linux-{x64,arm64}` in its published `files`, and
both nixpkgs pins resolve `prefetch-npm-deps` to the identical source so one hash serves
both.
