---
# dotfiles-3jw7
title: Add claude-code debug hook
status: completed
type: task
priority: normal
created_at: 2026-03-20T17:41:26Z
updated_at: 2026-03-20T20:08:54Z
order: V
---

A hook that matches everything and appends the contents of the hook into a file. The hook could always be installed, but bypassed if an env var is not set.

## Summary of Changes

Created `home/programs/claude-code/hooks/debug.nix` — a debug hook that registers on all 13 hook events and logs payloads to `/tmp/claude-hooks-debug/<session_id>.log`. Gated behind the `CLAUDE_DEBUG_HOOKS` env var (exits immediately if unset). Uses Nix-pinned `jq` to extract session ID from the stdin JSON payload. Added to `hooks/default.nix` imports.
