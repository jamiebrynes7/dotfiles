---
# dotfiles-m7np
title: Collapse maintaining-project-context
status: todo
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-15T15:33:10Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**File:** `home/lib/ai/skills/maintaining-project-context/SKILL.md` (182 → ~55 lines)

The When-to-Update table (48–59), the step-by-step process (61–130), the Decision Tree (132–152), and the Quick Reference (154–169) are four renderings of one rule: *update context files when contracts change, not when implementation changes*. It also re-derives `writing-claude-md-files` content despite declaring it a required sub-skill.

- [ ] Keep the AGENTS.md-vs-CLAUDE.md format detection and companion-pointer convention — non-obvious, repo-specific, unrecoverable from context
- [ ] Collapse the four duplicate renderings into one paragraph plus the git-diff commands
- [ ] Drop content that `writing-claude-md-files` owns (templates, freshness dates, the <100-line budget); rely on the declared sub-skill
- [ ] Run `nix flake check`
