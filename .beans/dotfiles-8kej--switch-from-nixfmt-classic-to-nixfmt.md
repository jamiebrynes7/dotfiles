---
# dotfiles-8kej
title: Switch from nixfmt-classic to nixfmt
status: completed
type: task
priority: normal
created_at: 2026-06-01T21:33:40Z
updated_at: 2026-06-06T16:56:38Z
---

Devshell eval shows:

> evaluation warning: nixfmt-classic is deprecated and unmaintained. We recommend switching to nixfmt.

We will want to reformat everything 

## Plan

- [x] Swap `nixfmt-classic` → `nixfmt` in flake.nix devShell
- [x] Swap in templates/projects/go/flake.nix
- [x] Swap in templates/projects/typescript/flake.nix
- [x] Update CLAUDE.md formatting convention text
- [x] Reformat all .nix files with new nixfmt
- [x] Run nix flake check

## Summary of Changes

Replaced the deprecated `nixfmt-classic` formatter with the official RFC 166-style `nixfmt` and reformatted the whole tree.

- Swapped `nixfmt-classic` → `nixfmt` in the devShell package lists: root `flake.nix` (`baseShellPkgs`), `templates/projects/go/flake.nix`, `templates/projects/typescript/flake.nix`.
- Updated the formatting convention note in `CLAUDE.md` to reference `nixfmt` (RFC 166 style).
- Reformatted all 47 tracked `.nix` files with the new `nixfmt` (40 changed; 7 were already conformant).
- Verified: `nixfmt --check` clean/idempotent, `nix flake check` passes (exit 0), no remaining `nixfmt-classic` references in code/docs/CI.
