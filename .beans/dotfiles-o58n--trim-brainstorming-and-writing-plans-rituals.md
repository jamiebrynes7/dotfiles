---
# dotfiles-o58n
title: Trim brainstorming and writing-plans rituals
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-16T09:23:46Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**Files:** `home/lib/ai/skills/brainstorming/SKILL.md` (127), `home/lib/ai/skills/writing-plans/SKILL.md` (243)

Both are mostly keeps — the HARD-GATE is a deliberate workflow guardrail (the article preserves strategic guardrails), and the plannotator/beans invocations are mechanism, which self-documenting-interface guidance says to keep.

- [x] `brainstorming` — cut Key Principles (120–127), which restates the Process section
- [x] `writing-plans` — cut the announcement ritual (line 14), an artifact of the 4.x structural-enforcement playbook
- [x] `writing-plans` — cut the Remember section (237–243), which restates Bite-Sized Granularity and No Placeholders
- [x] Leave `diff-scope` untouched — it is already the model of what the guidance asks for
- [ ] Run `nix flake check`

## Summary of Changes

Cut three 4.x-era rituals, left the mechanism alone.

- `brainstorming` (127 → 118): removed the Key Principles list, which restated the Process section verbatim. HARD-GATE and the plannotator integration untouched.
- `writing-plans` (243 → 233): removed the announcement ritual ("I'm using the writing-plans skill...") and the Remember section, which restated Bite-Sized Granularity and No Placeholders.
- `diff-scope` untouched, as specified.
