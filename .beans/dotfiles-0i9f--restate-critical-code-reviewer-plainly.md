---
# dotfiles-0i9f
title: Restate critical-code-reviewer plainly
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:32:59Z
updated_at: 2026-08-15T17:21:29Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-vmit
---

**File:** `home/lib/ai/skills/critical-code-reviewer/SKILL.md` (203 → ~130 lines)

The adversarial stance **stays** — the model default in review is agreeableness (fewer issues surfaced, severity softened), so the framing counteracts a real tendency. The problem is that it is performed rather than stated, and tuned hard enough to need its own counterweight.

Restate in place, do not delete:

- [x] "Guilty until proven exceptional" → Assume nothing works until the code demonstrates it does
- [x] "Every unhandled Promise will reject at 3 AM" → Unhandled rejections surface in production, not in review
- [x] "Structural contempt" → Code organisation reveals thinking; flag it
- [x] "Assume the worst intentions and the sloppiest habits" → Read for what the code does, not what it appears to intend
- [x] "An insult to the reader" → moves to `house-style-code-comments`

Keep: the diff-scope handoff, the cross-repo PRECONDITION guard (a real boundary, correctly forceful), the `pr-checkout.sh` steps, the four severity tiers, the response format, the subagent-mode note (179).

- [x] Compress (do not delete) the Slop Detector and Adversarial Lens lists (82–116) by roughly half — they work as recall aids
- [x] Keep **both** anti-manufacturing correctives (163, 203) through the rewrite. Drop one only after re-reading real review output and confirming honesty holds without it
- [x] Run `nix flake check`

## Summary of Changes

`critical-code-reviewer/SKILL.md`: 203 → 190 lines. The adversarial stance is preserved and restated plainly rather than performed.

The line count is well short of the ~110 estimate, and that estimate was simply wrong for this file. The theatre compressed as expected, but most of what remains is mechanism the bean says to keep — the PR-reference steps, the cross-repo guard, `pr-checkout.sh`, the response format. Two review rounds then restored content, which is the right trade.

**Restated, not cut:** "guilty until proven exceptional" → assume nothing works until the code shows it does; "every unhandled Promise will reject at 3 AM" → these surface in production, not in review; "structural contempt" → code organisation reveals thinking; "assume the worst intentions" → read for what the code does, not what it appears to intend. The new opening names the failure mode it is resisting (agreeableness — fewer issues surfaced, severity softened), which is a stronger instruction than the register it replaced because it says what to resist rather than performing a mood.

**Restored after subagent review** caught them missing from the first pass: the exhaustiveness mandate ("find every flaw, not just the ones that are easy to see") had no successor anywhere — the mapping covered stance but never coverage, which matters most in a skill whose purpose is countering under-reporting; the 500-line component threshold, the only concrete checkable number in its section; and unused variables in the dead-code item. Also merged "Operating Constraints" and "When Uncertain", which were two renderings of the same rule.

**Both deferred questions resolved in this PR at user request** (`dotfiles-hjsw`, `dotfiles-wpey`): dropped the redundant anti-manufacturing corrective, keeping the one attached to the approval decision; and promoted "Verify" from a dangling instruction to a real severity tier with a slot in the response template.
