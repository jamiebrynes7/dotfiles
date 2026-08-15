---
# dotfiles-nw9f
title: Rewrite writing-claude-directives for Claude 5
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:32:11Z
updated_at: 2026-08-15T16:12:13Z
parent: dotfiles-nj63
---

**File:** `home/lib/ai/skills/writing-claude-directives/SKILL.md` (272 lines → ~130)

This is the meta-skill every other directive here was written under, so it goes first — otherwise the next rewrite reproduces the same shape. The cuts are **factually stale**, not merely redundant.

Remove or restate:

- [x] Line 41 "Repetition enforces critical rules" — inverted; repetition across sources forces deliberation
- [x] Lines 74, 103, 249 — "Claude 4.x" calibration and overtriggering warnings
- [x] Line 39 "~150 instruction limit" — unsourced; real guidance is prune for conflict, not count
- [x] Line 151 "XML outperforms markdown for rule preservation" — a long-context workaround, not current guidance
- [x] Lines 224–232 — Opus 4.5 "think"-sensitivity note
- [x] Lines 90–99 — "Announce: I am using [skill]" structural enforcement (source of the announcement rituals elsewhere)
- [x] Lines 210–222 anti-overengineering block — cut as **duplication** with the harness system prompt, not because the rule is wrong

Keep: discovery/`description` guidance (how skills get found), naming, progressive disclosure, token targets.

Add:

- [x] The three cut criteria from the epic body
- [x] A rich-references section, subject to the portability constraint below
- [x] **Portability constraint** — skills deploy to `~/.claude/skills/<name>/` on every machine the flake touches and run against arbitrary projects, so a skill may reference only files shipped inside its own directory. Repo-relative paths dangle silently. Currently written down nowhere.
- [x] **Shared-policy extraction** — when 2+ skills need the same rule, extract it to its own skill and have each load it, rather than picking an owner and cross-referencing. Load order and co-presence are not guaranteed; skill loading is idempotent so a redundant load is free.
- [x] Run `nix flake check`

## Summary of Changes

`home/lib/ai/skills/writing-claude-directives/SKILL.md`: 272 → 115 lines.

Removed every stale item on the list above. Added the three cut criteria, a rich-references section, and shared-policy extraction.

**Portability landed elsewhere.** The constraint was written into the skill as specified, but user review caught that the version I wrote named `the flake`, `.cursor/skills`, `.codex/skills` and `crates/CLAUDE.md` — repo mechanics, inside a skill that deploys to every machine and runs in arbitrary projects. The rule is now split: the general form ("a skill may reference only files inside its own directory") stays in the skill, and the repo-specific mechanics moved to `home/lib/ai/CLAUDE.md` under Gotchas, with the freshness date bumped to 2026-08-15.

**Cut beyond the list**, all reported: Action Bias Templates (two verbatim XML blocks conveying one idea), the "By Skill Type" table, and the Workflows checkbox example (subsumed by task tracking). Positive-vs-negative framing and the "~150 instruction" heuristic also went — the first because the rewrite's own prose uses negation freely, so keeping the rule would have been self-contradictory.

**From subagent review:** retuned the line budget to two numbers (main file ~150, any reference ~500) after the single 500-line total was shown to condemn `devils-advocate`, the library's best progressive-disclosure example; removed a surviving unsourced overtriggering claim; dropped an incorrect "skill loading is idempotent, so a redundant load is free"; restored the placement rule and a validator/`scripts/` pattern that the file still gestured at; fixed a contradiction between "do not justify a cut with 'Claude already knows this'" and a "Explaining basics | Omit" table row.

`nix flake check` passes. The cross-reference from `writing-claude-md-files:9` ("token efficiency, compliance techniques, and directive structure") still resolves — the Compliance section survives and the description names it.
