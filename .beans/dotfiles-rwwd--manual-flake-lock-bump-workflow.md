---
# dotfiles-rwwd
title: Manual flake-lock bump workflow
status: in-progress
type: feature
priority: normal
created_at: 2026-10-06T15:17:50Z
updated_at: 2026-10-06T15:33:10Z
---

Add a `workflow_dispatch`-only GitHub workflow that refreshes `flake.lock`, re-pins the
nixpkgs-derived package hashes, and opens an auto-merging PR.

`flake.lock` is the single source of truth for every machine (`templates/systems/*` only declare
`dotfiles.url`), and lock bumps have been a manual habit that stopped in late July 2026.
`auto-update.yml` runs nightly but only touches `packages/*/update.sh`.

`nixos-26.05` and `nixpkgs-26.05-darwin` are the same `release-26.05` branch with two different
Hydra gates, so they can only differ in staleness, never in content — they move as one unit in one
PR. The ~6-monthly release bump (moving `nixos-X`/`nixpkgs-X-darwin`/`nix-darwin-X`/`release-X` in
lockstep) stays out of scope.

`ci.yml` is `ubuntu-latest` only, so `checks.aarch64-darwin` is never built in CI, and lock-bump PRs
auto-merge on Linux validation alone. A macOS leg was built and measured on #359: 20 min uncached, vs
11 min for Linux. It was split into a separate draft PR, to land once a build cache exists.

## Todo

- [x] `packages/beans/update.sh`: accept an optional rev positional alongside `--force`
- [x] `.github/workflows/update-flake-lock.yml`: new manual workflow
- [x] `CLAUDE.md`: note how lock bumps happen
- [x] Verify locally: re-force beans + paseo at recorded rev/version is a no-op; `nix flake check` on darwin
- [x] On the PR: CI green (macOS leg also passed in 20 min before being split out)
- [ ] After merge: `gh workflow run update-flake-lock.yml`; the PR body shows the input diff, `packages/` has hash-only changes, and auto-merge lands it

## Notes

- `packages/beans/update.sh` also swapped `grep -oP` (GNU-only, so the script failed on macOS) for a portable `awk` extraction. Verified: re-pinning at the recorded rev rewrites `data.json` byte-identically.
- `nix flake update` writes its report to **stderr**: a `•` line at column 0, then the old ref indented 4 spaces and the `→` new ref indented 2. Confirmed against a scratch flake; the workflow's grep matches it.
- macOS CI was parked rather than landed: 20 min per run uncached. Running it surfaced and fixed a real aarch64-darwin build crash in beans-frontend (dotfiles-62ow, #360).
