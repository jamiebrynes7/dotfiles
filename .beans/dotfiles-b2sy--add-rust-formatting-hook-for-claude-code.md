---
# dotfiles-b2sy
title: Add Rust formatting hook for Claude Code
status: todo
type: feature
priority: normal
created_at: 2026-05-24T14:36:19Z
updated_at: 2026-05-24T14:37:18Z
---

Add a Claude Code hook that runs `cargo fmt` automatically when a Rust file (`*.rs`) is edited.

## Context

Scope: **local to the dotfiles repo only** — configured in `.claude/settings.json` at the repo root, NOT deployed globally via home-manager. This hook only fires when Claude is working inside this repo.

## Todo

- [ ] Create / update `.claude/settings.json` at the dotfiles repo root
- [ ] Add a PostToolUse hook matching Edit|Write|MultiEdit that runs `rustfmt` on the edited file when its path ends in `.rs`
- [ ] Use the tool input's `file_path` (via `$CLAUDE_TOOL_INPUT` / jq) to target just the edited file
- [ ] Make the hook a no-op when `rustfmt` isn't on PATH (don't block the edit)
- [ ] Confirm `.claude/settings.json` isn't gitignored so the hook ships with the repo
- [ ] Test by editing a `.rs` file and confirming it gets formatted
