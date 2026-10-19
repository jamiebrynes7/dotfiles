---
# dotfiles-l710
title: Add the paseo flake input pinned to v0.3.1
status: scrapped
type: task
priority: normal
created_at: 2026-08-19T10:54:52Z
updated_at: 2026-10-15T10:00:58Z
parent: dotfiles-pg0j
---

**Files:**
- Modify: `flake.nix` (the `inputs` block, after the `crane` entry)
- Modify: `flake.lock` (generated)

Context: paseo's own flake pins `nixpkgs-unstable`. We follow our `nixpkgs` so the package is built against this repo's pin — that is what makes the `npmDepsHash` ours to own rather than upstream's to break. Pinned to `v0.3.1` deliberately (not `v0.4.0`).

Work from inside the devShell (`direnv` shell) so `nixfmt` is on `PATH` for the pre-commit hook.

- [ ] **Step 1: Add the input**

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

- [ ] **Step 2: Lock the input**

Run: `nix flake lock`
Expected: `warning: updating lock file ...` plus a line adding `paseo`. `flake.lock` is modified.

- [ ] **Step 3: Verify the input resolves and the flake still evaluates**

Run: `nix flake metadata --json | jq -r '.locks.nodes.paseo.locked.rev'`
Expected: a 40-character commit sha (the v0.3.1 tag's commit), not an error.

Run: `nix eval .#lib --apply builtins.attrNames`
Expected: `[ "mkDarwin" "mkHomeManagerSystem" "mkNixosSystem" "mkShells" ]`

- [ ] **Step 4: Format check**

Run: `nixfmt --check flake.nix`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add flake.nix flake.lock
git commit -m "flake: add paseo input pinned to v0.3.1

Bean: dotfiles-l710"
```

## Reasons for Scrapping

Superseded. This work landed through a different route under dotfiles-ajpl (e6a50de, "packages/paseo: vendor paseo and add a home-manager module"). paseo comes from `packages/paseo`, which `callPackage`s upstream's `nix/package.nix` out of a `fetchFromGitHub` source. There is no flake input, no `overlays/` directory and no v0.3.1 pin. `home/programs/paseo.nix` already carries `hostnames`, `extraPath`, `environment` and `environmentCommand`, and later the plugins option (dotfiles-5nj7). Nothing in this plan is left to build against the current code.
