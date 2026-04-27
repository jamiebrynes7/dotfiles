---
# dotfiles-4d6w
title: Skip hash recomputation when upstream version is unchanged
status: todo
type: task
priority: normal
created_at: 2026-04-27T10:46:13Z
updated_at: 2026-04-27T10:46:13Z
parent: dotfiles-fo1w
---

Make `packages/*/update.sh` cheap to re-run when nothing changed upstream: resolve the upstream version, compare it to the version already recorded in the package's metadata file, and exit early without running any hash computation when they match.

Parent: dotfiles-fo1w.

## Behavior

- Resolve the target version exactly as today (CLI arg if given, else latest GitHub release / latest `main` commit for beans).
- Read the existing version from the metadata file in the same directory:
  - `packages/cship/hashes.json` → `.version`
  - `packages/plannotator/hashes.json` → `.version`
  - `packages/beans/data.json` → `.version` (note: includes `unstable-DATE-SHA`, so equality check is exact-string).
- If the resolved version equals the recorded version, print `"<pkg> already at <version>, skipping"` and exit 0 before any `nix-prefetch-url` / `nix store prefetch-file` / `nix-build` calls.
- If the metadata file is missing or has no version, fall through to the normal update path.
- Honor a `--force` (or equivalent) flag to bypass the early-exit when the user explicitly wants to recompute hashes, e.g. when a hash format changed or a previous run wrote bad data.

## Todo

- [ ] Implement the version-equality early-exit in `packages/cship/update.sh`.
- [ ] Implement the same in `packages/plannotator/update.sh`.
- [ ] Implement the same in `packages/beans/update.sh` (note: version string includes commit SHA, so this naturally captures "main hasn't moved").
- [ ] Add a `--force` (or equivalent) escape hatch to all three.
- [ ] Test: run each script twice in a row, confirm the second run does no network or hash work and exits quickly.
- [ ] Test: confirm `--force` still does the full update when invoked explicitly.
