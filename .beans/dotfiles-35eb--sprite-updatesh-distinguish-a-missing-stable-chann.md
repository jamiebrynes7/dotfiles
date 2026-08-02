---
# dotfiles-35eb
title: 'sprite update.sh: distinguish a missing stable channel from a transient failure'
status: todo
type: task
priority: low
created_at: 2026-08-02T14:01:42Z
updated_at: 2026-08-02T14:01:42Z
parent: dotfiles-fo1w
---

https://sprites-binaries.t3.storage.dev/client/release.txt currently 404s, so `packages/sprite/update.sh` always falls through to the rc channel — the fallback is the happy path today, not the error path.

Once sprite ships a stable release, a transient 5xx on `release.txt` will silently downgrade `hashes.json` from the stable version back to an rc, and nothing in the script or the workflow compares version ordering to catch it.

## Todo

- [ ] Only fall back to `rc.txt` on an HTTP 404; treat other failures as fatal

Raised in review of dotfiles-j5ab.
