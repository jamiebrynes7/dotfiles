---
# dotfiles-moh7
title: Use the nimbus binary cache in CI
status: in-progress
type: task
priority: normal
created_at: 2026-11-15T14:08:44Z
updated_at: 2026-11-15T14:22:21Z
---

Substitute from and push to nimbus.jb7.sh in ci.yml, per nimbus's docs/runbooks/github-actions.md.

- [x] Wire netrc read token (from 1Password) and niks3-action into ci.yml
- [x] User: mint read token, store in 1Password, create OIDC trust rule
- [ ] Verify a master run pushes and a later run substitutes

## Notes

FlakeHub login (enabled by id-token: write) overrides netrc-file; nimbus netrc merged via /etc/determinate/config.json additionalNetrcSources. FlakeHub 401 noise remains (nix-installer-action#261).
