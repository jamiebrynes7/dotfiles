---
# dotfiles-1gkw
title: 'claude-reauth: detect the login time-limit messages'
status: completed
type: bug
created_at: 2026-11-24T11:08:27Z
updated_at: 2026-11-24T11:08:27Z
---

Claude Code 2.1.329 fails with "Failed to authenticate: this login reached its time limit and cannot be renewed..." when a login hits its maximum lifetime; the plugin didn't recognise it, so no re-login card appeared.

## Summary of Changes

Added the three time-limit wordings from the 2.1.329 binary to shared/detect.ts (exact-match list), plus two phrases for the anywhere-in-reply match. Recovery is unchanged: it already runs `claude auth login`.
