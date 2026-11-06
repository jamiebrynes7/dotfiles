---
# dotfiles-fj6j
title: Bump paseo-chat-polish to 0.9.1 and add a manual bump script
status: completed
type: task
priority: normal
created_at: 2026-11-06T10:08:04Z
updated_at: 2026-11-06T10:09:20Z
---

Re-pin packages/paseo-plugin-paseo-chat-polish to upstream main (v0.9.1). Add a hand-run bump script that is deliberately not named update.sh, so the nightly auto-update.yml (which globs packages/*/update.sh) leaves it alone.

- [x] Add packages/paseo-plugin-paseo-chat-polish/bump.sh
- [x] Re-pin to 41395d5 (v0.9.1)
- [x] Build the package
- [x] Update CLAUDE.md packages section

## Summary of Changes

Re-pinned paseo-chat-polish from 0.7.0 (0782cd0) to 0.9.1 (41395d5, tip of upstream main) with fresh src and npmDepsHash. Added a hand-run bump.sh that resolves a rev (default: the default branch), prefetches both hashes against the pinned nixpkgs, rewrites default.nix, and prints the compare URL, the package.json files list and the paseo requirement for review. It is named bump.sh so auto-update.yml skips it. Documented in CLAUDE.md.
