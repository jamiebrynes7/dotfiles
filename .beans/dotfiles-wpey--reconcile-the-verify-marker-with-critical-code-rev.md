---
# dotfiles-wpey
title: Reconcile the "Verify" marker with critical-code-reviewer severity tiers
status: completed
type: bug
priority: low
created_at: 2026-08-15T16:48:12Z
updated_at: 2026-08-15T17:21:11Z
parent: dotfiles-nj63
---

Pre-existing, not introduced by the restatement rewrite.

`critical-code-reviewer/SKILL.md` tells the reviewer to mark uncertain findings as "Verify" rather than "Blocking" (twice, in "When You Can't Be Sure"), but "Verify" is not one of the four severity tiers (Blocking / Required Changes / Strong Suggestions / Noted) and has no slot in the response-format template. A reviewer following the instruction has nowhere to put the result.

- [ ] Either add Verify as a tier with a template section, or fold it into an existing tier
- [ ] Update both call sites and the response format consistently

## Summary of Changes

Done immediately rather than deferred — user review said to add it to the template.

"Verify" is now a real tier rather than a dangling instruction. It appears in all three places that needed it: the instruction in "When You Can't Be Sure" (line 122), the severity tiers as tier 5 (line 136), and its own section in the response-format template (line 180).
