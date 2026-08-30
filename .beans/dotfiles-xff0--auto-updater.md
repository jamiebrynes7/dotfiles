---
# dotfiles-xff0
title: Auto-updater
status: draft
type: feature
priority: normal
created_at: 2026-07-10T16:05:32Z
updated_at: 2026-07-10T16:05:32Z
---

It would be nice to have some kind of auto-update mechanism whereby we install a service/user-service (depending on whether its a nixos/darwin/home-manager one) to:

1. Pull from the system-specific upstream
2. Run `just update`.
3. Apply, commit, and push.

This should no-op if the working directory is dirty. We need to have some kind of feedback mechanism if this breaks. 
