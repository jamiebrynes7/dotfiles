---
# dotfiles-bf5n
title: 'beans/update.sh: use flake-pinned nixpkgs for hash computations'
status: completed
type: bug
priority: normal
created_at: 2026-05-24T14:51:53Z
updated_at: 2026-05-24T14:55:31Z
---

## Problem

`packages/beans/update.sh` computes `vendorHash` and `pnpmDepsHash` using `<nixpkgs>` (the user's NIX_PATH channel). However, `nix flake check` evaluates the package using the flake-pinned `nixos-25.11` nixpkgs.

When the two diverge (e.g., different `pnpm` versions in `fetchPnpmDeps`), the script writes a hash that fails to validate during `nix flake check`. The user just ran `update.sh` and the recomputed `pnpmDepsHash` is wrong — the original hash in `data.json` was actually correct.

`vendorHash` happens to be stable because Go vendor hashes only depend on `go.sum` content, but the same class of bug would bite there too.

## Fix

Resolve `inputs.nixpkgs.outPath` from the flake via `nix eval --impure --expr 'builtins.getFlake ...'`, then pass `-I nixpkgs=$PATH` to the `nix-build` calls so they evaluate against the same nixpkgs the flake uses.

## Todos

- [x] Pin nixpkgs lookup in update.sh to the flake's `inputs.nixpkgs`
- [x] Restore the original `pnpmDepsHash` in `data.json` (revert the bad write)
- [x] Verify by re-running `update.sh` and confirming `data.json` matches the original

## Summary of Changes

- `packages/beans/update.sh` now resolves `inputs.nixpkgs.outPath` from the flake via `nix eval --impure --expr` and passes `-I nixpkgs=$PATH` to both `nix-build` invocations. Hashes are now computed against the same nixpkgs that `nix flake check` uses.
- Re-ran the script after the fix; `pnpmDepsHash` came back as the original `sha256-jvvI97UXo5V4NcoiDUAA3/jRngrce+AZAluRXKJnJAw=`, and `git diff packages/beans/data.json` is empty.
