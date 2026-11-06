---
# dotfiles-xz6j
title: Load poppet-bot credentials from 1Password in workflows
status: in-progress
type: task
priority: normal
created_at: 2026-11-06T22:47:22Z
updated_at: 2026-11-06T22:53:25Z
---

Replace POPPET_BOT_CLIENT_ID / POPPET_BOT_PRIVATE_KEY repo config with 1password/load-secrets-action reading op://dev/poppet-bot-github, following nimbus infra.yml.

- [x] archive-beans.yml
- [x] auto-update.yml
- [x] update-flake-lock.yml

- [x] Verify with a real workflow run
- [ ] Delete POPPET_BOT_PRIVATE_KEY secret and POPPET_BOT_CLIENT_ID variable once verified
