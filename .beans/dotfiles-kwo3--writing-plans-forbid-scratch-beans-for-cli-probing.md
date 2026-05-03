---
# dotfiles-kwo3
title: 'writing-plans: forbid scratch beans for CLI probing'
status: completed
type: bug
priority: normal
created_at: 2026-05-03T14:32:41Z
updated_at: 2026-05-03T14:36:36Z
---

The writing-plans skill caused the agent to create a throwaway 'test' bean (dotfiles-swdj) to validate beans CLI output format during plan generation. Test beans pollute the registry permanently. Add guidance to the skill telling the agent the existing detection is sufficient and to proceed directly without probing the CLI.

- [x] Edit home/lib/ai/skills/writing-plans/SKILL.md to add guidance against creating probe/scratch beans
- [x] Delete the stray .beans/dotfiles-swdj--test.md file
- [x] Commit changes

## Summary of Changes

Added a paragraph in the writing-plans SKILL.md Output Mode section that:
- Tells the agent the first bean it creates is the epic — no probing needed.
- Explains why test/scratch beans are harmful (durable artifacts that pollute the registry).
- Points the agent at `beans check` as the non-destructive sanity-check escape hatch.

Also deleted the stray `.beans/dotfiles-swdj--test.md` left behind by the offending agent run.
