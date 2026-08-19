---
# dotfiles-l710
title: Add the paseo flake input pinned to v0.3.1
status: completed
type: task
priority: normal
created_at: 2026-08-19T10:54:52Z
updated_at: 2026-08-19T12:45:32Z
parent: dotfiles-pg0j
---

**Files:**
- Modify: `flake.nix` (the `inputs` block, after the `crane` entry)
- Modify: `flake.lock` (generated)

Context: paseo's own flake pins `nixpkgs-unstable`. We follow our `nixpkgs` so the package is built against this repo's pin — that is what makes the `npmDepsHash` ours to own rather than upstream's to break. Pinned to `v0.3.1` deliberately (not `v0.4.0`).

Work from inside the devShell (`direnv` shell) so `nixfmt` is on `PATH` for the pre-commit hook.

- [x] **Step 1: Add the input**

In `flake.nix`, inside `inputs`, after the `crane.url` line:

```nix
    # Self-hosted orchestrator for AI coding agents. Pinned to a tag: paseo's
    # release tags ship a stale nix/npm-deps.hash, so overlays/paseo.nix has to
    # supply a matching hash for whatever tag is pinned here. Bump both together.
    paseo = {
      url = "github:getpaseo/paseo/v0.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [x] **Step 2: Lock the input**

Run: `nix flake lock`
Expected: `warning: updating lock file ...` plus a line adding `paseo`. `flake.lock` is modified.

- [x] **Step 3: Verify the input resolves and the flake still evaluates**

Run: `nix flake metadata --json | jq -r '.locks.nodes.paseo.locked.rev'`
Expected: a 40-character commit sha (the v0.3.1 tag's commit), not an error.

Run: `nix eval .#lib --apply builtins.attrNames`
Expected: `[ "mkDarwin" "mkHomeManagerSystem" "mkNixosSystem" "mkShells" ]`

- [x] **Step 4: Format check**

Run: `nixfmt --check flake.nix`
Expected: no output, exit 0.

- [x] **Step 5: Commit**

```bash
git add flake.nix flake.lock
git commit -m "flake: add paseo input pinned to v0.3.1

Bean: dotfiles-l710"
```

## Summary of Changes

Added the `paseo` flake input to `flake.nix`, after the `crane` entry, pinned to tag
`v0.3.1` with `inputs.nixpkgs.follows = "nixpkgs"`, and locked it.

- `flake.nix` — 8-line `inputs` entry with a comment recording the coupling to
  `overlays/paseo.nix` (both must be bumped together, since release tags ship a stale
  `nix/npm-deps.hash`).
- `flake.lock` — purely additive: one `paseo` node (`rev bfec7ac3`, the `v0.3.1` tag
  commit) plus `root.inputs.paseo`. No existing input moved.

Verified: locked rev matches `refs/tags/v0.3.1^{}`; `nix eval .#lib --apply
builtins.attrNames` still yields `[ "mkDarwin" "mkHomeManagerSystem" "mkNixosSystem"
"mkShells" ]`; `nixfmt --check flake.nix` clean. The input is inert until
`overlays/paseo.nix` consumes it — no `packages.*`/`checks.*` surface change.

### Review notes

Subagent review approved with no blocking or required changes; user review requested no
changes. Two points were raised and deliberately not actioned here:

1. The `follows` does **not** make `npmDepsHash` ours, contrary to this bean's Context
   paragraph — `dotfiles-rdkr` consumes `inputs.paseo` as a source tree
   (`"${inputs.paseo}/nix/package.nix"`), so paseo's flake outputs never evaluate and
   `final` decides the nixpkgs. The follows still earns its keep by keeping a second
   `nixpkgs` node out of `flake.lock`. Implementation matches the spec as written
   (`docs/specs/2026-08-19-paseo-home-manager-module.md`); only the recorded rationale is
   off.
2. The one hardcoded hash must satisfy both `nixpkgs` and `nixpkgs-darwin`, while CI only
   runs `nix flake check` on linux — captured as `dotfiles-egs1` to resolve during
   `dotfiles-rdkr`.

Not landed on its own: held on the shared `feature/paseo-package-wiring` branch to ship
as one PR with `dotfiles-rdkr`, so the comment's reference to `overlays/paseo.nix` is
never transiently dangling on `master`.
