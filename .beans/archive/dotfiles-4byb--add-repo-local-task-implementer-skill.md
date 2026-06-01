---
# dotfiles-4byb
title: Add repo-local task-implementer skill
status: completed
type: task
priority: normal
created_at: 2026-05-31T13:50:31Z
updated_at: 2026-05-31T13:51:29Z
---

Add a repo-local Claude Code skill at .claude/skills/task-implementer/SKILL.md that guides an agent through implementing a bean end-to-end.

The skill workflow:
1. Read the bean (beans show)
2. Validate the bean & flag discrepancies to the user for resolution before coding
3. Implement
4. Subagent code review (prefer critical-code-reviewer skill if available)
5. Mark the bean done + commit (code + bean file together)

## Todos
- [x] Write SKILL.md with frontmatter (user-invocable) and the 5-step workflow
- [x] Verify discovery/format against existing repo skill conventions

## Summary of Changes

Added `.claude/skills/task-implementer/SKILL.md` — a repo-local Claude Code skill that drives a bean from start to finish:

1. **Read** — `beans show` plus a GraphQL pull of parent/children/blockedBy for context.
2. **Validate** — a checklist (clear scope, unblocked, status fits, internally consistent, no stale assumptions) with a hard STOP that surfaces discrepancies to the user before any code is written.
3. **Implement** — follow the bean plan, check off todos as they land, run `cargo test --workspace` / `nix flake check`.
4. **Subagent review** — hand the diff to a fresh agent, preferring the critical-code-reviewer skill; triage by severity tier.
5. **Done + commit** — append a Summary of Changes, mark completed, commit code and bean file together using the repo's `<area>: <summary> (id)` convention.

Description follows the writing-claude-directives 'Use when...' discovery format; no allowed-tools restriction so the skill can use the full toolset.
