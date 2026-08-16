---
# dotfiles-m7np
title: Collapse maintaining-project-context
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-16T09:23:46Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**File:** `home/lib/ai/skills/maintaining-project-context/SKILL.md` (182 → ~55 lines)

The When-to-Update table (48–59), the step-by-step process (61–130), the Decision Tree (132–152), and the Quick Reference (154–169) are four renderings of one rule: *update context files when contracts change, not when implementation changes*. It also re-derives `writing-claude-md-files` content despite declaring it a required sub-skill.

- [x] Keep the AGENTS.md-vs-CLAUDE.md format detection and companion-pointer convention — non-obvious, repo-specific, unrecoverable from context
- [x] Collapse the four duplicate renderings into one paragraph plus the git-diff commands
- [x] Drop content that `writing-claude-md-files` owns (templates, freshness dates, the <100-line budget); rely on the declared sub-skill
- [ ] Run `nix flake check`

## Summary of Changes

Collapsed `maintaining-project-context/SKILL.md` from 182 to 46 lines.

The When-to-Update table, the four-step process, the Decision Tree, the Quick Reference, and the Common Mistakes table were five renderings of one rule; that rule is now stated once in Core Principle ("update when contracts change, not when implementation changes") with the change taxonomy inline.

Kept the non-recoverable, repo-specific parts: AGENTS.md-vs-CLAUDE.md format detection, the companion-pointer convention, the git-diff commands, and the lowest-level-that-applies hierarchy rule. Dropped templates, freshness dates, and the line budget — `writing-claude-md-files` is the declared sub-skill and owns them.
