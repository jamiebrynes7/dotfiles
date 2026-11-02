---
# dotfiles-l5ts
title: 'brainstorming: ask question rounds via structured question tool'
status: completed
type: task
priority: normal
created_at: 2026-10-26T14:31:21Z
updated_at: 2026-10-26T14:31:36Z
---

Direct the brainstorming skill to ask question rounds via AskUserQuestion (or the assistant's equivalent structured question tool), falling back to the text format when none is available.

- [x] Update home/lib/ai/skills/brainstorming/SKILL.md
- [x] PR and land

## Summary of Changes

The brainstorming skill's Question rounds section now directs each round through the assistant's structured question tool (AskUserQuestion in Claude Code): candidate answers as options, recommendation first and marked (Recommended), rounds split across calls when the tool caps questions per call. The plain-text ➡️ format remains as the fallback when no such tool exists.
