---
# dotfiles-0i9f
title: Restate critical-code-reviewer plainly
status: todo
type: task
priority: normal
created_at: 2026-08-15T15:32:59Z
updated_at: 2026-08-15T15:33:10Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-vmit
---

**File:** `home/lib/ai/skills/critical-code-reviewer/SKILL.md` (203 → ~130 lines)

The adversarial stance **stays** — the model default in review is agreeableness (fewer issues surfaced, severity softened), so the framing counteracts a real tendency. The problem is that it is performed rather than stated, and tuned hard enough to need its own counterweight.

Restate in place, do not delete:

- [ ] "Guilty until proven exceptional" → Assume nothing works until the code demonstrates it does
- [ ] "Every unhandled Promise will reject at 3 AM" → Unhandled rejections surface in production, not in review
- [ ] "Structural contempt" → Code organisation reveals thinking; flag it
- [ ] "Assume the worst intentions and the sloppiest habits" → Read for what the code does, not what it appears to intend
- [ ] "An insult to the reader" → moves to `house-style-code-comments`

Keep: the diff-scope handoff, the cross-repo PRECONDITION guard (a real boundary, correctly forceful), the `pr-checkout.sh` steps, the four severity tiers, the response format, the subagent-mode note (179).

- [ ] Compress (do not delete) the Slop Detector and Adversarial Lens lists (82–116) by roughly half — they work as recall aids
- [ ] Keep **both** anti-manufacturing correctives (163, 203) through the rewrite. Drop one only after re-reading real review output and confirming honesty holds without it
- [ ] Run `nix flake check`
