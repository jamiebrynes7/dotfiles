---
# dotfiles-vmit
title: Extract house-style-code-comments skill
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:32:11Z
updated_at: 2026-08-15T16:24:19Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**New:** `home/lib/ai/skills/house-style-code-comments/SKILL.md` (~25 lines)

The comment policy is currently stated three times at three strictness levels: `coding-effectively:148-156` ("omit entirely"), `comment-cleanup:34-61` ("no exceptions"), `critical-code-reviewer:86,92` ("an insult to the reader").

Designating one owner and cross-referencing does not work — nothing guarantees `coding-effectively` is loaded when a review skill runs, and a PR review may never trigger the write-code skill at all. Extract to a shared skill instead, following the `diff-scope` idiom (`**REQUIRED**: Load the <skill> skill`).

- [x] Create the skill with `cc:user-invocable: false`. One strictness level, stated once: why-not-what, the removal categories, the four acceptable-comment cases
- [x] `coding-effectively` — drop 148–156, add the REQUIRED load line
- [x] `comment-cleanup` — drop 34–61, add the REQUIRED load line. Keep what is genuinely its own: the subagent-delegation protocol, the `git diff -U0` verification step, the finding format (121 → ~40 lines)
- [x] `critical-code-reviewer` — drop the comment bullets, add the REQUIRED load line
- [x] Run `nix flake check` (catches skill-name collisions via the `mkSkillFiles` assertions)

Side benefit: the policy becomes independently editable instead of requiring three files and three phrasings to be reconciled.

## Summary of Changes

New skill `home/lib/ai/skills/house-style-code-comments/SKILL.md` (44 lines) is now the single statement of the comment policy. All three consumers load it via the `**REQUIRED**: Load the '<skill>' skill` idiom; `comment-cleanup` drops 121 → 95 lines.

**A policy conflict surfaced and was resolved deliberately.** The three copies had drifted: `coding-effectively` endorsed explaining "why a non-obvious approach was chosen over the obvious one", while `comment-cleanup` unconditionally removed comments that "argue with an approach that is not in the code". Nothing forced a resolution before, because no agent ever loaded both. The first draft of the merge silently picked the ban. Now stated explicitly: the line is whether a concrete failure mode is named — "the obvious `map` here deadlocks under concurrent writes" stays, "rather than a map" goes.

**From subagent review:** disambiguated `comment-cleanup:59` where the recursion guard said "do not have it load this skill" — with `house-style-code-comments` named 20 words earlier, the nearest-antecedent reading inverted the instruction and would have left the subagent judging against no criteria at all; narrowed an overbroad "the reasoning behind a change belongs in the commit message" that had grown to cover the entire keep-list four lines below it; fixed a stale "criteria above" reference; removed a surviving framing restatement; and mapped the policy's categories onto the reviewer's severity tiers at the `critical-code-reviewer` call site, since that consumer reports rather than edits.

`nix flake check` passes — no skill-name collision. User review returned no changes.
