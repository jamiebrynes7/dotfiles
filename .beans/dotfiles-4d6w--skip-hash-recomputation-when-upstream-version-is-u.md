---
# dotfiles-4d6w
title: Skip hash recomputation when upstream version is unchanged
status: completed
type: task
priority: normal
created_at: 2026-04-27T10:46:13Z
updated_at: 2026-07-10T16:18:59Z
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

- [x] Implement the version-equality early-exit in `packages/cship/update.sh`.
- [x] Implement the same in `packages/plannotator/update.sh`.
- [x] Implement the same in `packages/beans/update.sh` (note: version string includes commit SHA, so this naturally captures "main hasn't moved").
- [x] Add a `--force` (or equivalent) escape hatch to all three.
- [x] Test: run each script twice in a row, confirm the second run does no network or hash work and exits quickly.
- [x] Test: confirm `--force` still does the full update when invoked explicitly.

## Summary of Changes

Added a version-equality early-exit to all three `packages/*/update.sh` scripts so re-running them is cheap when nothing changed upstream:

- **cship / plannotator**: after resolving the target version, read `.version` from `hashes.json` and, if it matches, print `"<pkg> already at <version>, skipping"` and `exit 0` before the tag-existence check and any `nix store prefetch-file` calls.
- **beans**: reordered so the latest-`main` commit is fetched (and `VERSION` computed) *before* the `nix eval` nixpkgs resolution; the guard compares against `.version` in `data.json`. Since the version embeds the commit SHA, equality also means "main hasn't moved". The expensive `nix eval`/`nix-build` work is now skipped on the no-op path.
- All three gained a `-f`/`--force` flag (via a proper arg-parse loop) to bypass the early-exit and recompute hashes. Unknown options are rejected.
- Missing/empty metadata (`jq ... // empty`, errors suppressed) falls through to the normal update path.

Tested: cship/plannotator/beans each skip on a matching recorded version and exit 0 with no network/hash work; `--force` proceeds through the full update and rewrites the metadata byte-identically.
