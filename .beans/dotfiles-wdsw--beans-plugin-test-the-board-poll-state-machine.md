---
# dotfiles-wdsw
title: 'beans plugin: test the board poll state machine'
status: todo
type: task
priority: low
created_at: 2026-11-06T14:44:57Z
updated_at: 2026-11-06T14:44:57Z
parent: dotfiles-oweh
---

The client poll in `ts/paseo-plugin-beans/client/use-board.ts` (serialised request chain, forced refresh while busy, failed-fingerprint backoff, error-banner clearing, dropping results after unmount or workspace change) has no tests; every node:test covers server/shared code.

## What to build

Extract the poll's state machine into a plain function under `shared/` that takes the two RPCs and a timer, keep `useBoard` as a thin React wrapper over it, and cover it with node:test.

## Acceptance criteria

- [ ] A refresh pressed while a request is in flight runs once the chain ends
- [ ] A fingerprint failure followed by a success clears the error without refetching an unchanged board
- [ ] A board load that fails is not retried until the fingerprint moves or the user retries
- [ ] Results arriving after stop (unmount or workspace change) are dropped
