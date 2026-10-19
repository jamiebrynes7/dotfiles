---
# dotfiles-yk15
title: paseo docs
status: scrapped
type: feature
priority: normal
created_at: 2026-08-19T10:54:38Z
updated_at: 2026-10-15T10:00:58Z
parent: dotfiles-7043
---

Documents the new `overlays/` directory and the convention it establishes.

Owns:
- `CLAUDE.md` — the Project Structure tree, the Packages convention section, and the freshness date

## Reasons for Scrapping

Superseded. This work landed through a different route under dotfiles-ajpl (e6a50de, "packages/paseo: vendor paseo and add a home-manager module"). paseo comes from `packages/paseo`, which `callPackage`s upstream's `nix/package.nix` out of a `fetchFromGitHub` source. There is no flake input, no `overlays/` directory and no v0.3.1 pin. `home/programs/paseo.nix` already carries `hostnames`, `extraPath`, `environment` and `environmentCommand`, and later the plugins option (dotfiles-5nj7). Nothing in this plan is left to build against the current code.
