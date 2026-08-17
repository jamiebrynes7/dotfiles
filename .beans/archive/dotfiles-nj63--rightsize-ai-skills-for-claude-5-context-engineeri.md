---
# dotfiles-nj63
title: Rightsize AI skills for Claude 5 context engineering
status: completed
type: epic
priority: normal
created_at: 2026-08-15T15:30:44Z
updated_at: 2026-08-16T09:24:21Z
---

**Goal:** Rework `home/lib/ai/` skills and the claude-code skill-reinforcement hook against Anthropic's Claude 5 context-engineering guidance, cutting ~54% of directive lines without losing behaviour that is actually load-bearing.

**Source:** https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models

**Approved plan:** `~/.claude/plans/can-you-review-https-claude-com-blog-the-zesty-sonnet.md` — read this before starting any child task; it holds the per-file line references and rationale.

## Cut criteria

Every cut must be justified against one of these. "Claude already knows this" is explicitly **not** a valid justification.

1. **Taste vs consensus** — taste stays; nothing else tells the model which side of a contested choice we're on.
2. **Counteracts a default vs restates one** — rules resisting a known model tendency (happy-path bias, review agreeableness) are the most valuable thing a skill holds.
3. **Cost to say** — cut elaboration, worked examples, and justification paragraphs. Keep the rule as a one-liner.

Plus two independent grounds: **factually stale** (4.x-calibrated guidance now wrong) and **duplicated across sources**.

**When unsure: demote to `references/`, don't delete.** Being wrong that way is cheap.

## Constraints

- Skills deploy to `~/.claude/skills/<name>/` on **every machine this flake is applied to** and run against arbitrary projects. A skill may reference only files shipped inside its own directory — repo-relative paths dangle silently elsewhere.
- `nix flake check` is the gate (nixfmt + skill-name conflict assertions).

## Summary of Changes

All 12 child beans completed. `home/lib/ai/` markdown is down from 2,891 to 1,803 lines (~38%), plus the skill-reinforcement hook no longer fires on every prompt.

Landed across the epic:

- Disabled the skill-reinforcement hook by default (retained, not deleted)
- `coding-effectively` trimmed to rules; `house-style-code-comments` extracted as the single owner of the comment policy
- `writing-claude-directives` rewritten for Claude 5; `critical-code-reviewer` restated plainly, with the Verify marker and the anti-manufacturing correctives reconciled
- `global-instructions` rewritten as three rules of intent instead of scripted utterances
- `maintaining-project-context` collapsed (182 → 46); `writing-claude-md-files` trimmed (301 → 108)
- `devils-advocate` references compressed (1,068 → 588 across the three), calibration untouched
- `brainstorming` and `writing-plans` rituals cut; `diff-scope` left alone

Every cut was justified against the epic's criteria — taste over consensus, counteracts-a-default over restates-one, and cost-to-say — not against "Claude already knows this".
