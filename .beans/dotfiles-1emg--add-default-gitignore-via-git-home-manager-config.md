---
# dotfiles-1emg
title: Add default .gitignore via git home-manager config
status: completed
type: feature
priority: normal
created_at: 2026-04-28T17:29:03Z
updated_at: 2026-04-28T17:30:42Z
---

Configure a default global .gitignore in the git home-manager module so common OS-generated files are ignored across all repos.

## Context

The git program module lives at `home/programs/git/` (or similar). home-manager's `programs.git` exposes `ignores` (a list) and/or `extraConfig.core.excludesfile` for a global ignore file.

## Initial entries

- `.DS_Store` — macOS Finder metadata files

Future additions can be appended as we discover other noisy files worth globally ignoring.

## Todo

- [x] Locate the git module under `home/programs/` (`home/programs/git.nix`)
- [x] Add `.DS_Store` to the global ignore list (prefer `programs.git.ignores`)
- [x] Run `nix flake check --impure` to validate
- [x] Verify the resulting `~/.config/git/ignore` (or equivalent) contains the entry after a home-manager switch

## Summary of Changes

Added `programs.git.ignores = [ ".DS_Store" ];` to `home/programs/git.nix`. home-manager renders this to `~/.config/git/ignore`, which git uses as a global excludesFile. Validated with `nix flake check --impure`.

Future noisy files can be appended to the same list.
