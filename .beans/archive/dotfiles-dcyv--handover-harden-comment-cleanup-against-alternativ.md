---
# dotfiles-dcyv
title: 'Handover: Harden comment-cleanup against alternatives-not-taken'
status: completed
type: task
priority: normal
created_at: 2026-08-01T20:29:42Z
updated_at: 2026-08-01T20:35:36Z
---

Context
~/.claude/skills/comment-cleanup/SKILL.md
 (105 lines) ran on a NixOS module and passed a set of comments that a separately-dispatched, adversarially-prompted subagent then cut by ~60%. Root cause analysis of that gap:
1.
The skill licenses the exact comments that should die. Line 56 lists as acceptable: “Why a non-obvious approach was chosen over the obvious one.” That sentence is a standing permit for // the obvious way would be X, but.... Such comments pass the skill’s why-not-what test while being worthless — they answer a question the reader never asked, and they rot as the alternative drifts out of relevance.
2.
Self-review doesn’t work here. The skill ran in the context of the agent that had just written the comments. Each one felt load-bearing because that agent remembered the bug behind it. No wording change fixes this; only a reviewer with no stake in the code does.
3.
Criteria without a default disposition let the reviewer settle at its own comfort level.
Goal
Close the licence, add a default disposition, and delegate the cutting judgment to a subagent while keeping factual verification with the caller.
Changes
1. Fix ### 2. Value Assessment → “Acceptable comments” (lines 54-59). Delete the “non-obvious approach was chosen over the obvious one” bullet. Replace the list with:
- **Why** a workaround exists, linking the issue or bug when possible
- **Why** a particular value, threshold, or constraint was picked
- A load-bearing subtlety whose removal would silently break something
- Domain or business context that cannot be expressed in code

2. Add to “Remove unconditionally” (after line 44):
- Argues with an approach that is not in the code (`// rather than X`, `// the obvious way would be Y, but`). These pass the why-not-what test yet answer a question the reader never asked, and they age badly as the alternative loses relevance. Bug-fix archaeology belongs in the commit message.

3. Add a default disposition as the second paragraph of ### 2. Value Assessment (after line 36):
Default to removal. Keep a comment only when you can name the specific wrong action a reader would take without it -- a change they would make that silently breaks something. "It adds useful context" is not an answer.

4. Add a new section between ## Analysis and ## Output:
## Delegating the judgment pass

Dispatch a subagent to decide what to cut, then verify its work.

An author cannot review their own comments: having written the code, every comment feels load-bearing because the bug behind it is still fresh. A reviewer with no stake in the change carries no such attachment.

Give the subagent the in-scope files, the criteria above, and the framing that it is a principal engineer whose default answer to "should this comment exist?" is no. Have it apply edits directly.

Verify before reporting:

1. No non-comment lines changed -- diff the file with comment lines stripped.
2. Every surviving factual claim is true. A fresh-context reviewer cuts well but asserts badly, so check each claim against the code and its actual runtime behaviour.

Verify
•
Construct a diff containing a comment of the form // rather than X, because... and run 
/comment-cleanup
. It should be cut, and the finding should cite the alternatives-not-taken rule.
•
Confirm a genuinely load-bearing comment survives (one where removing the described operator/flag silently changes behaviour).
•
Confirm the skill still loads diff-scope first and still emits the **file:line** - [severity] finding format.
•
wc -l SKILL.md — expect ~125.
Notes / constraints
•
Do not convert this into a standalone agent definition. It would lose the 
/comment-cleanup
 invocation and the diff-scope integration. The skill stays the entry point and dispatches internally.
•
Leave the YAML frontmatter alone. The description triggers are working; changing them risks discovery.
•
Step 2 of the verification list is load-bearing, not ceremony: in the run that motivated this, the subagent cut correctly but introduced a false claim (“stdio closed” for fds redirected to 
/dev/null
). Ruthlessness and accuracy traded off, and the caller caught it.
•
Per writing-claude-directives: prefer context over imperatives, keep positive framing, and don’t let the file grow past ~500 lines. Avoid stacking MUST/CRITICAL on the new rules — the motivation paragraphs are doing the work.
•
Don’t introduce an exception for “what” comments; that rule is fine as-is.

## Summary of Changes

Hardened `home/lib/ai/skills/comment-cleanup/SKILL.md` (105 -> 121 lines) per the handover:

1. Removed the "Why a non-obvious approach was chosen over the obvious one" bullet from **Acceptable comments** and replaced the list with why-a-workaround / why-a-value / load-bearing-subtlety / domain-context.
2. Added a **Remove unconditionally** bullet for comments that argue with an approach not in the code, with the rationale that they pass the why-not-what test while answering a question nobody asked.
3. Added a "Default to removal" paragraph as the second paragraph of `### 2. Value Assessment`.
4. Added `## Delegating the judgment pass` between the Analysis criteria and `## Output`.

Beyond the handover, a subagent review caught that the new section had no handoff contract with `## Output`, so three seams were closed: the subagent now returns findings in the `**file:line**` format against pre-edit line numbers (previously nothing produced findings at all); `### Applying Fixes` states its removals and rewrites are already on disk (previously a double-apply); and its pass is scoped as subtractive, leaving **Add** findings with the caller. Verification step 1 was also made mechanizable -- `git diff -U0` instead of "diff the file with comment lines stripped", which needs per-language parsing.

Frontmatter, the diff-scope load, and the finding format are untouched. `nix flake check` passes; user review requested no changes.

Two reviewer findings were surfaced and consciously left as-is: the new Remove bullet can collide with the acceptable why-a-workaround bullet, and "a load-bearing subtlety" is the one acceptable bullet not shaped as *why*, in tension with the no-exceptions-for-what rule. Follow-up: dotfiles-olcp (Cursor/Codex portability of the dispatch instruction).
