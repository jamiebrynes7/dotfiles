---
# dotfiles-x60r
title: Strengthen plannotator options-review trigger in brainstorming skill
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:23:55Z
updated_at: 2026-05-03T14:24:53Z
---

The brainstorming skill currently softens the plannotator options-review step in prose (lines 50-52 of SKILL.md), making it easy for agents to skip and present options inline instead. The inline-approval phrasing in the 'Presenting the design' subsection also leaks backwards, framing inline approval as a generally acceptable review mechanism.

## Tasks

- [x] Rewrite lines 50-52 (Exploring approaches bullets) so plannotator invocation is an explicit step, not a parenthetical, with motivation for why file-based review beats inline
- [x] Scope the inline-approval bullet in 'Presenting the design' so it's clearly specific to the design walkthrough, not a general pattern

## Summary of Changes

**home/lib/ai/skills/brainstorming/SKILL.md**

- Rewrote the two bullets under **Exploring approaches** (lines 50–52) so the plannotator options-review invocation is an explicit step rather than a parenthetical aside. Added motivation: file-anchored annotations capture structured feedback that inline chat replies lose.
- Reworded the inline-approval bullet under **Presenting the design** (line 57) to scope inline approval to the design walkthrough specifically, calling out that options and the final spec both go through plannotator instead.

Left the existing HARD-GATE block untouched per discussion — the rewrite plus scoping should be enough without adding a second gate.
