---
# dotfiles-p4l3
title: Trim writing-claude-md-files
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-16T09:24:03Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**File:** `home/lib/ai/skills/writing-claude-md-files/SKILL.md` (301 → ~100 lines)

Two full templates, a ~45-line synthetic auth example, then a Common Mistakes table and a Checklist restating the same rules a third and fourth time.

Keep:

- [x] Top-level vs subdirectory distinction (the actual insight)
- [x] The section lists
- [x] Freshness-date requirement with `date +%Y-%m-%d` — a real hallucination guard; models will invent a date
- [x] The no-`@`-syntax rule — a real, non-obvious token cost

**Do NOT point at repo files.** Replacing the synthetic example with a pointer to `home/lib/ai/CLAUDE.md` or `crates/CLAUDE.md` was explicitly rejected: `mkSkillFiles` deploys this skill to `~/.claude/skills/` on every machine the flake is applied to, and it runs in arbitrary projects. Those paths exist nowhere else and fail silently.

- [x] Cut the two templates and the Common Mistakes table (both restate the section lists)
- [x] Keep one compact synthetic example, self-contained in the file, roughly a third of the current auth walkthrough
- [x] Cut the Checklist — with templates gone, the section lists serve that purpose
- [ ] Run `nix flake check`

## Summary of Changes

Trimmed `writing-claude-md-files/SKILL.md` from 301 to 108 lines.

Cut the two full templates, the Common Mistakes table, the top-level-vs-subdirectory heuristics table, and the Checklist — all four restated the section lists. The ~45-line auth example is now a ~30-line one, self-contained in the file, with a closing note on what its Purpose section deliberately does *not* say.

Kept the load-bearing content: the top-level (HOW) vs subdirectory (WHY/contracts) distinction, both section lists, the mandatory freshness date with `date +%Y-%m-%d` as a hallucination guard, the no-`@`-syntax rule, and the line budgets.

No repo-relative paths introduced — the example stays synthetic, since this skill deploys to `~/.claude/skills/` on every machine and runs in arbitrary projects.
