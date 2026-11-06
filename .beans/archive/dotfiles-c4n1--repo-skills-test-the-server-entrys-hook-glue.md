---
# dotfiles-c4n1
title: 'repo-skills: test the server entry''s hook glue'
status: completed
type: task
priority: low
created_at: 2026-11-06T11:11:28Z
updated_at: 2026-11-06T11:59:35Z
parent: dotfiles-l44k
---

`ts/paseo-plugin-repo-skills/index.server.ts` is untested. Add a node:test case with a fake `server.addHook` that pins: the returned request keeps `env` and other request-level keys; the alsoMatched log; the catch path returning void. Deferred from the dotfiles-ki8f review (S6).

## Summary of Changes

Done as part of dotfiles-1p9i: the hook wiring moved to `server/hooks.ts`, and `server/hooks.test.ts` drives create.before → open.before → create.after with a fake `addHook` and `paseo`. It pins env and request-key preservation, the several-matches row, the catch path, and append failures.
