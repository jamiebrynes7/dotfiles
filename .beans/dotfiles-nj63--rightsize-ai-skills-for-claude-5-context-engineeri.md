---
# dotfiles-nj63
title: Rightsize AI skills for Claude 5 context engineering
status: todo
type: epic
created_at: 2026-08-15T15:30:44Z
updated_at: 2026-08-15T15:30:44Z
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
