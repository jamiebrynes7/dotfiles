---
# dotfiles-1gkw
title: 'claude-reauth: detect the login time-limit messages'
status: completed
type: bug
priority: normal
created_at: 2026-11-24T11:08:27Z
updated_at: 2026-11-24T11:14:01Z
---

Claude Code 2.1.329 fails with "Failed to authenticate: this login reached its time limit and cannot be renewed..." when a login hits its maximum lifetime; the plugin didn't recognise it, so no re-login card appeared.

## Summary of Changes

Added the three time-limit wordings from the 2.1.329 binary to shared/detect.ts (exact-match list), plus two phrases for the anywhere-in-reply match. Recovery is unchanged: it already runs `claude auth login`.

Follow-up: dropped a trailing period the binary doesn't have from the "· Sign in again to continue" entry, and added the "your claude.ai login expired" phrase (a billing_error whose fix is also `claude auth login`).
