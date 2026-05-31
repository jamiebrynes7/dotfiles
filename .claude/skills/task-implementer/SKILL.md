---
name: task-implementer
description: Use when asked to implement a bean, work on a bean, or pick up a task by its bean id (e.g. "implement dotfiles-4byb", "work on this bean"). Drives the full loop — read, validate, implement, subagent review, user review, then mark done and commit.
---

# Task Implementer

Implement a bean end-to-end: read it, confirm it is actually ready, build it, get it reviewed, and land it. The discipline that matters most here is **not skipping validation** — implementing a half-specified or blocked bean wastes work and produces the wrong thing. Surface problems to the user before writing code, not after.

Track progress through the steps below by keeping the bean's own todo items current as you go (`- [ ]` → `- [x]`).

## Step 1 — Read the bean

```bash
beans show --json <id>
```

Also pull the surrounding context, because a task rarely makes sense alone:

```bash
beans query --json '{ bean(id: "<id>") { title body status type priority parent { id title body status } children { id title status } blockedBy: blockedBy { id title status } } }'
```

Read the parent for intent and acceptance criteria, and note any children — a bean with children is usually a container and should not be implemented directly.

## Step 2 — Validate, and stop if anything is off

Check the bean against this list before touching code:

- **Scope is clear** — you can state what "done" looks like and what files/areas it touches.
- **Not blocked** — every `blockedBy` bean is `completed`, and no ancestor is blocked. The CLI's own `ready`/`next` logic respects this; an unfinished blocker means stop.
- **Status fits** — it is `todo` or `in-progress`, not `draft` (needs refinement), `completed`, or `scrapped`.
- **Internally consistent** — todo items, description, and parent intent do not contradict each other.
- **No stale assumptions** — references to code, files, or APIs in the bean still match reality. Verify the ones the work depends on.

If everything checks out, set the bean in-progress (`beans update <id> -s in-progress`) and continue.

**If anything is ambiguous, contradictory, blocked, or out of date — STOP.** Present the specific discrepancies to the user as a short list and ask how to resolve them. Do not guess and proceed, and do not silently "fix" the bean's intent. Resolving a discrepancy may mean editing the bean body, splitting it, or unblocking a dependency — let the user decide. Resume implementation only once the bean is coherent and unblocked.

## Step 3 — Implement

Follow the bean's plan and the repo's conventions (see the root and nearest `CLAUDE.md`). Check off each todo item on the bean as you complete it, so the bean reflects real progress:

```bash
beans update <id> --body-replace-old "- [ ] <item>" --body-replace-new "- [x] <item>"
```

Validate your work the way the repo expects — for Rust changes run `cargo test --workspace`; for a broader check run `nix flake check` (this is what CI runs). Do not move on with failing tests.

## Step 4 — Subagent code review

Hand the change to a fresh subagent for review rather than reviewing your own work — a second context catches what the implementing one rationalizes away. Prefer the **critical-code-reviewer** skill if it is available; otherwise dispatch a general review agent. Scope the review to the diff for this bean and give the reviewer the bean's acceptance criteria so it can check intent, not just style.

Triage the findings: address Blocking and Required items before landing. For Suggestions, apply the worthwhile ones and offer the rest to the user as optional follow-up beans. Re-run the repo's validation after any fixes.

## Step 5 — User code review

Before committing, request a review from the user — the subagent checks the code, but only the user can confirm it matches what they actually wanted. Use the **plannotator-user-code-review** skill to collect structured annotations, then address each item. Re-run the repo's validation after any changes.

Treat this as a gate: do not commit until the user's review is resolved.

## Step 6 — Mark done and commit

Only when every todo item on the bean is checked and both reviews are resolved:

1. Add a `## Summary of Changes` section describing what was done, and set the bean completed:

   ```bash
   beans update <id> -s completed --body-append "## Summary of Changes

   <what changed and why>"
   ```

2. Commit the **code changes and the bean file together** in one commit. The bean's state and the code it describes must never drift apart. Follow the repo's commit convention — subject `<area>: <imperative summary>` with the bean id appended, e.g. `home/programs/foo: add bar (dotfiles-4byb)`.

Commit and push only when the user has asked you to; if unsure, stage the work and confirm. After landing, offer follow-up beans for anything deferred.
