---
# dotfiles-c42i
title: Update project templates to Nixpkgs 26.05
status: completed
type: task
priority: normal
created_at: 2026-06-06T17:39:36Z
updated_at: 2026-08-02T09:52:08Z
---

## Summary of Changes

Bumped the `nixpkgs` input pin in both project templates from `nixos-25.11` to `nixos-26.05`, matching the root flake:

- `templates/projects/go/flake.nix`
- `templates/projects/typescript/flake.nix`

The system templates (`templates/systems/*`) don't pin nixpkgs — they consume it via the `dotfiles` flake input — so they needed no change.

Verified by building `devShells.x86_64-linux.default` for both templates against 26.05; every package resolves (go, gopls, gotools, golangci-lint, nil, nixfmt, nodejs). `nixfmt --check` passes.
