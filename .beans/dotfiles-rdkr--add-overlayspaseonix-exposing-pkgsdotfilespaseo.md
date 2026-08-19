---
# dotfiles-rdkr
title: Add overlays/paseo.nix exposing pkgs.dotfiles.paseo
status: todo
type: task
priority: normal
created_at: 2026-08-19T10:55:26Z
updated_at: 2026-08-19T10:59:27Z
parent: dotfiles-pg0j
blocked_by:
    - dotfiles-l710
---

**Files:**
- Create: `overlays/paseo.nix` (new top-level `overlays/` directory)
- Modify: `flake.nix` — the `defaultOverlays` list

Context: upstream's `nix/package.nix` exposes `npmDepsHash` as a **function argument** precisely so downstream flakes on a different nixpkgs can supply their own. `buildNpmPackage` destructures it, so `overrideAttrs` cannot reach it — `callPackage` with an explicit argument is the supported route, and is cleaner than the `npmDeps.overrideAttrs` hack in `sys-warbird`.

The overlay must be appended **after** `dotfilesOverlay` in `defaultOverlays`, because that one plain-assigns `dotfiles` and would otherwise clobber this. Extending with `(prev.dotfiles or { }) // { ... }` matches `crates/default.nix`.

- [ ] **Step 1: Create `overlays/paseo.nix` with a placeholder hash**

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

- [ ] **Step 2: Wire it into `defaultOverlays`**

In `flake.nix`, append to the `defaultOverlays` list (after the `crates` entry):

```nix
      defaultOverlays = [
        inputs.alacritty-themes.overlays.default
        dotfilesOverlay
        (import ./crates { inherit inputs; })
        (import ./overlays/paseo.nix { inherit inputs; })
      ];
```

- [ ] **Step 3: Verify the attribute exists (eval only, no build)**

Run: `nix eval --raw .#packages.aarch64-darwin.paseo.name`
Expected: `paseo-0.3.1`

If this errors with `attribute 'paseo' missing`, the overlay is ordered before `dotfilesOverlay` or the `dotfiles` merge is wrong.

- [ ] **Step 4: Resolve the real `npmDepsHash`**

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

- [ ] **Step 5: Verify the node-pty patch landed**

Run: `ls $(nix build .#packages.aarch64-darwin.paseo --no-link --print-out-paths)/lib/paseo/packages/server/node_modules/node-pty/prebuilds`
Expected: a non-empty directory listing. An empty result or `No such file` means the `postInstall` did not apply.

- [ ] **Step 6: Format check**

Run: `nixfmt --check flake.nix overlays/paseo.nix`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add flake.nix overlays/paseo.nix
git commit -m "overlays: add patched paseo as pkgs.dotfiles.paseo

Bean: dotfiles-rdkr"
```
