---
# dotfiles-0dzp
title: Re-pin repo-local plugins' paseo SDK when paseo updates
status: completed
type: task
priority: normal
created_at: 2026-10-18T13:58:23Z
updated_at: 2026-10-18T14:09:11Z
---

`packages/paseo/update.sh` bumps `hashes.json`, but every `ts/paseo-plugin-*` pins `@getpaseo/plugin` to the exact paseo version, so each nightly bump goes red on `<dir>-sdk-version` until someone re-pins by hand. Make the update re-pin automatically.

Breaking SDK changes stay caught: CI's `nix flake check` runs each plugin's `<dir>-typecheck` against the re-pinned SDK, so an incompatible release sits red on the auto-update PR, which is the desired outcome.

## Acceptance criteria

- [x] A paseo update re-pins `@getpaseo/plugin` in every `ts/paseo-plugin-*/package.json` and refreshes its `package-lock.json` to that version
- [x] Single-write discipline holds: if the SDK version isn't resolvable on npm yet (or npm fails), `update.sh` fails and leaves `hashes.json` and every plugin's files untouched
- [x] Idempotent: re-running at the recorded version still exits 0 without touching anything
- [x] `<dir>-sdk-version` failure message and `CLAUDE.md` point at the automated path rather than a manual re-pin
- [x] `nix flake check` green

## Summary of Changes

- New `ts/update-paseo-sdk.sh VERSION` re-pins `@getpaseo/plugin` in every `ts/paseo-plugin-*`. It runs `npm pkg set` and `npm install --package-lock-only` with the flake's nodejs and an explicit npmjs registry, all in a staging copy, and copies back only the files that changed.
- `packages/paseo/update.sh`:
  - probes npm for the SDK version early, next to the desktop-asset check, so an unpublished SDK fails fast;
  - renders `hashes.json` to a temp file, runs the re-pin as the last fallible step, then copies it into place, so a failure leaves everything untouched;
  - the skip path at the recorded version is unchanged.
- `<dir>-sdk-version`'s failure message, `CLAUDE.md` and the auto-update PR body now point at the automated path. A breaking SDK change still shows up as a red `<dir>-typecheck` on the update PR.
- Verified:
  - re-pin at the current version is a no-op;
  - re-pin to a missing 9.9.9 exits 1 with nothing touched;
  - a 0.11.3 ↔ 0.11.4 round trip restores the files exactly;
  - `update.sh` skips with no arguments, and `update.sh --force` end to end leaves the tree unchanged (`hashes.json` stays 0644);
  - `nix flake check` passes.
