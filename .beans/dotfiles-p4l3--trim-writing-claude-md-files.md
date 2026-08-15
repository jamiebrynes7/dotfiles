---
# dotfiles-p4l3
title: Trim writing-claude-md-files
status: todo
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-15T15:33:10Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**File:** `home/lib/ai/skills/writing-claude-md-files/SKILL.md` (301 → ~100 lines)

Two full templates, a ~45-line synthetic auth example, then a Common Mistakes table and a Checklist restating the same rules a third and fourth time.

Keep:

- [ ] Top-level vs subdirectory distinction (the actual insight)
- [ ] The section lists
- [ ] Freshness-date requirement with `date +%Y-%m-%d` — a real hallucination guard; models will invent a date
- [ ] The no-`@`-syntax rule — a real, non-obvious token cost

**Do NOT point at repo files.** Replacing the synthetic example with a pointer to `home/lib/ai/CLAUDE.md` or `crates/CLAUDE.md` was explicitly rejected: `mkSkillFiles` deploys this skill to `~/.claude/skills/` on every machine the flake is applied to, and it runs in arbitrary projects. Those paths exist nowhere else and fail silently.

- [ ] Cut the two templates and the Common Mistakes table (both restate the section lists)
- [ ] Keep one compact synthetic example, self-contained in the file, roughly a third of the current auth walkthrough
- [ ] Cut the Checklist — with templates gone, the section lists serve that purpose
- [ ] Run `nix flake check`
