---
# dotfiles-56hj
title: Add pin-file marker to opt packages out of auto-updates
status: todo
type: task
priority: normal
created_at: 2026-04-27T10:46:23Z
updated_at: 2026-04-27T10:46:23Z
parent: dotfiles-fo1w
---

Allow pinning a package to its currently-recorded version by dropping a marker file into the package directory. When the marker is present, `update.sh` exits 0 immediately and performs no network or hash work, so the scheduled `update-dependencies-*` job leaves the package alone.

Parent: dotfiles-fo1w.

## Behavior

- Decide on one filename and use it consistently across all packages. Suggested: `.pinned` (hidden, doesn't clutter `ls`) — final choice deferred to implementation, but pick one and stick with it.
- Optional contents: if the file is non-empty, treat its first line as a human-readable reason and include it in the log message. An empty file is also valid.
- When the marker exists in the package directory:
  - Print `"<pkg> pinned (<reason or 'no reason given'>), skipping"`.
  - Exit 0 before any version resolution, network call, or hash computation.
- When the marker does not exist, behavior is unchanged.
- The pin lives in the package's source dir (not in CI config), so the pin and the package definition stay in lockstep across branches.

## Documentation

- Document the convention in a single place developers will find it — likely a short section in `packages/` (a README, or extending `CLAUDE.md` if there is one), covering: filename, semantics, optional reason line, and how to unpin (delete the file).

## Todo

- [ ] Pick the marker filename and document the choice in the bean before implementing.
- [ ] Add the pin-check at the top of `packages/cship/update.sh`.
- [ ] Add the pin-check at the top of `packages/plannotator/update.sh`.
- [ ] Add the pin-check at the top of `packages/beans/update.sh`.
- [ ] Document the convention so future packages follow the same pattern.
- [ ] Test: drop the marker file, run `update.sh`, confirm it exits 0 with no network activity. Remove the marker, confirm normal operation resumes.
- [ ] Confirm the scheduled `update-dependencies-*` workflow does not produce a PR for a pinned package.
