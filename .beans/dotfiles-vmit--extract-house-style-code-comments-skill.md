---
# dotfiles-vmit
title: Extract house-style-code-comments skill
status: todo
type: task
priority: normal
created_at: 2026-08-15T15:32:11Z
updated_at: 2026-08-15T15:33:10Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**New:** `home/lib/ai/skills/house-style-code-comments/SKILL.md` (~25 lines)

The comment policy is currently stated three times at three strictness levels: `coding-effectively:148-156` ("omit entirely"), `comment-cleanup:34-61` ("no exceptions"), `critical-code-reviewer:86,92` ("an insult to the reader").

Designating one owner and cross-referencing does not work — nothing guarantees `coding-effectively` is loaded when a review skill runs, and a PR review may never trigger the write-code skill at all. Extract to a shared skill instead, following the `diff-scope` idiom (`**REQUIRED**: Load the <skill> skill`).

- [ ] Create the skill with `cc:user-invocable: false`. One strictness level, stated once: why-not-what, the removal categories, the four acceptable-comment cases
- [ ] `coding-effectively` — drop 148–156, add the REQUIRED load line
- [ ] `comment-cleanup` — drop 34–61, add the REQUIRED load line. Keep what is genuinely its own: the subagent-delegation protocol, the `git diff -U0` verification step, the finding format (121 → ~40 lines)
- [ ] `critical-code-reviewer` — drop the comment bullets, add the REQUIRED load line
- [ ] Run `nix flake check` (catches skill-name collisions via the `mkSkillFiles` assertions)

Side benefit: the policy becomes independently editable instead of requiring three files and three phrasings to be reconciled.
