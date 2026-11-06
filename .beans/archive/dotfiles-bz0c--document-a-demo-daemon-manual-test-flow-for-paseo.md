---
# dotfiles-bz0c
title: Document a demo-daemon manual test flow for paseo plugins
status: completed
type: task
priority: normal
created_at: 2026-11-06T15:06:33Z
updated_at: 2026-11-06T15:11:22Z
---

Turn the throwaway demo daemon used to review the beans plugin into a repeatable manual test flow: a script that runs an isolated paseo daemon with chosen repo plugins on a spare port, a beans seed script, and docs.

## Acceptance criteria

- [x] `ts/paseo-demo.sh <id>...` builds the named `pkgs.dotfiles.paseo-plugin-<id>` packages and runs an isolated daemon (own PASEO_HOME, own port) that the desktop app can add as a host, without touching the user's real daemon
- [x] `ts/paseo-plugin-beans/demo/seed.sh` (run by `ts/paseo-demo.sh`) creates a dummy beans project covering epics in each status, blocked/scrapped/implicit-status beans, tags and a Markdown body, plus an empty repo, and registers both as workspaces on the demo daemon
- [x] The root CLAUDE.md documents the flow next to the repo-local plugin notes

## Summary of Changes

- `ts/paseo-demo.sh <id>...` sits next to `ts/update-paseo-sdk.sh`, the existing home for tooling that acts on every plugin.
  - It builds each `pkgs.dotfiles.paseo-plugin-<id>` and writes a fresh `/tmp/paseo-demo-home/config.json` that loads them.
  - It runs `paseo-server` on `127.0.0.1:6868`, then runs each plugin's `demo/seed.sh` once the daemon is listening.
  - On exit, Ctrl-C or SIGTERM, it stops the daemon with `paseo daemon stop`.
- `ts/paseo-plugin-beans/demo/seed.sh` recreates the review demo: a beans project with epics in three statuses, plus blocked, scrapped, draft, implicit-status, tagged and Markdown-bodied beans, and an empty git repo. It registers both as workspaces.
- `ts/default.nix`'s `pluginSource` now leaves `demo/` out, so seeds never ship in a plugin package.
- The root CLAUDE.md documents the flow next to the repo-local plugin notes.
- Verification:
  - A full run: build, seed, plugin running, then SIGTERM teardown with no daemon left behind.
  - shellcheck on both scripts.
  - All 21 `paseo-plugin-*` checks plus nixfmt.
