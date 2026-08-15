---
# dotfiles-nw9f
title: Rewrite writing-claude-directives for Claude 5
status: todo
type: task
created_at: 2026-08-15T15:32:11Z
updated_at: 2026-08-15T15:32:11Z
parent: dotfiles-nj63
---

**File:** `home/lib/ai/skills/writing-claude-directives/SKILL.md` (272 lines → ~130)

This is the meta-skill every other directive here was written under, so it goes first — otherwise the next rewrite reproduces the same shape. The cuts are **factually stale**, not merely redundant.

Remove or restate:

- [ ] Line 41 "Repetition enforces critical rules" — inverted; repetition across sources forces deliberation
- [ ] Lines 74, 103, 249 — "Claude 4.x" calibration and overtriggering warnings
- [ ] Line 39 "~150 instruction limit" — unsourced; real guidance is prune for conflict, not count
- [ ] Line 151 "XML outperforms markdown for rule preservation" — a long-context workaround, not current guidance
- [ ] Lines 224–232 — Opus 4.5 "think"-sensitivity note
- [ ] Lines 90–99 — "Announce: I am using [skill]" structural enforcement (source of the announcement rituals elsewhere)
- [ ] Lines 210–222 anti-overengineering block — cut as **duplication** with the harness system prompt, not because the rule is wrong

Keep: discovery/`description` guidance (how skills get found), naming, progressive disclosure, token targets.

Add:

- [ ] The three cut criteria from the epic body
- [ ] A rich-references section, subject to the portability constraint below
- [ ] **Portability constraint** — skills deploy to `~/.claude/skills/<name>/` on every machine the flake touches and run against arbitrary projects, so a skill may reference only files shipped inside its own directory. Repo-relative paths dangle silently. Currently written down nowhere.
- [ ] **Shared-policy extraction** — when 2+ skills need the same rule, extract it to its own skill and have each load it, rather than picking an owner and cross-referencing. Load order and co-presence are not guaranteed; skill loading is idempotent so a redundant load is free.
- [ ] Run `nix flake check`
