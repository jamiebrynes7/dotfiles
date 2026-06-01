---
# dotfiles-spyq
title: Wire --dev through the binaries + docs
status: completed
type: feature
priority: normal
created_at: 2026-05-30T18:31:49Z
updated_at: 2026-05-31T14:39:11Z
parent: dotfiles-z3aj
---

Parse and thread the `--dev` flag through both binaries and document the workflow. Owns `crates/beansd/src/main.rs`, `crates/beansd/src/run.rs`, `crates/beansctl/src/main.rs`, and `crates/CLAUDE.md`.

## Summary of Changes

All three tasks completed: `beansctl` gained a global `--dev` flag that routes to the dev socket; `beansd` parses `--dev` and threads it into `run()` for both the config and socket paths; and `crates/CLAUDE.md` documents the workflow.
