---
name: task-implementer
description: Use when asked to implement a bean, work on a bean, or pick up a task by its bean id (e.g. "implement dotfiles-4byb", "work on this bean"). Drives the full loop — read, validate, branch, implement, subagent review, user review, then land via a PR with auto-merge.
---

# Task Implementer

Implement a bean end-to-end: read it, confirm it is actually ready, build it, get it reviewed, and land it. The discipline that matters most here is **not skipping validation** — implementing a half-specified or blocked bean wastes work and produces the wrong thing. Surface problems to the user before writing code, not after.

A bean describes **what** to deliver — the behaviour and its acceptance criteria — not how. Working out the how, against the code as it is now, is this skill's job. Track progress by checking off the bean's acceptance criteria as each is met (`- [ ]` → `- [x]`).

## Step 1 — Read the bean

```bash
beans show --json <id>
```

Also pull the surrounding context, because a task rarely makes sense alone:

```bash
beans query --json '{ bean(id: "<id>") { title body status type priority parent { id title body status } children { id title status } blockedBy: blockedBy { id title status } } }'
```

Read the parent for intent, and note any children — a bean with children is usually a container and should not be implemented directly.

If the bean (or its parent epic) points at a spec, read the referenced sections. The spec holds the decisions — interfaces, option shapes, testing seams, verified upstream facts — that the bean deliberately does not repeat.

## Step 2 — Validate, and stop if anything is off

Check the bean against this list before touching code:

- **Done is observable** — you can state the behaviour the bean delivers and how each acceptance criterion will be checked.
- **Criteria can fail** — each acceptance criterion is not already true at the current `master`. One that already holds, or that only another bean's work could satisfy, is a discrepancy to raise.
- **Not blocked** — every `blockedBy` bean is `completed`, and no ancestor is blocked. The CLI's own `ready`/`next` logic respects this; an unfinished blocker means stop.
- **Status fits** — it is `todo` or `in-progress`, not `draft` (needs refinement), `completed`, or `scrapped`.
- **Internally consistent** — acceptance criteria, description, spec, and parent intent do not contradict each other.
- **No stale assumptions** — references to code, files, or APIs in the bean still match reality. Verify the ones the work depends on. Specs are point-in-time records, so drift between a spec and the code is expected and the code wins; stop only when the drift changes what this bean must deliver.

If everything checks out, set the bean in-progress (`beans update <id> -s in-progress`) and continue.

**If anything is ambiguous, contradictory, blocked, or out of date — STOP.** Present the specific discrepancies to the user as a short list and ask how to resolve them. Do not guess and proceed, and do not silently "fix" the bean's intent. Resolving a discrepancy may mean editing the bean body, splitting it, or unblocking a dependency — let the user decide. Resume implementation only once the bean is coherent and unblocked.

## Step 3 — Branch

Implement on a dedicated branch, never directly on `master`. Each bean is a vertical slice that lands on its own, so it gets its own branch named `<type>/<slug>` (e.g. `task/refine-task-implementer-skill`) — use the bean's `slug` field from `beans show`.

```bash
git checkout -b <type>/<slug>
```

If you are already on the right non-`master` branch for this unit of work, stay on it.

## Step 4 — Implement

Explore the code the bean touches before changing it, then decide the approach — following the spec's decisions and the repo's conventions (see the root and nearest `CLAUDE.md`). If the code contradicts something the spec or bean assumed, stop and raise it as in Step 2 rather than working around it.

Work test-first against the testing seam the spec or epic names (an existing check, test suite, or harness): extend it so it expresses an acceptance criterion, watch it fail, implement until it passes. Where a criterion cannot be checked automatically, note how you verified it.

Check off each acceptance criterion as it is met, so the bean reflects real progress:

```bash
beans update <id> --body-replace-old "- [ ] <criterion>" --body-replace-new "- [x] <criterion>"
```

Older beans may carry a step-by-step checklist instead of acceptance criteria. Treat those steps as a guide, verify their code against the repo before using it, and check them off as you go.

Validate your work the way the repo expects — for Rust changes run `cargo test --workspace`; for a broader check run `nix flake check` (this is what CI runs). Do not move on with failing tests.

## Step 5 — Subagent code review

Hand the change to a fresh subagent for review rather than reviewing your own work — a second context catches what the implementing one rationalizes away. Prefer the **critical-code-reviewer** skill if it is available; otherwise dispatch a general review agent. Scope the review to the diff for this bean and give the reviewer the bean's acceptance criteria so it can check intent, not just style.

Triage the findings: address Blocking and Required items before landing. For Suggestions, apply the worthwhile ones and offer the rest to the user as optional follow-up beans. Re-run the repo's validation after any fixes.

## Step 6 — User code review

Before committing, request a review from the user — the subagent checks the code, but only the user can confirm it matches what they actually wanted. Use the **plannotator-user-code-review** skill to collect structured annotations, then address each item. Re-run the repo's validation after any changes.

Treat this as a gate: do not commit until the user's review is resolved.

## Step 7 — Mark done and commit

Only when every acceptance criterion on the bean is checked and both reviews are resolved:

1. Add a `## Summary of Changes` section describing what was done, and set the bean completed:

   ```bash
   beans update <id> -s completed --body-append "## Summary of Changes

   <what changed and why>"
   ```

2. Commit the **code changes and the bean file together** in one commit on the branch. The bean's state and the code it describes must never drift apart. Follow the repo's commit convention (see the root `CLAUDE.md`).

## Step 8 — Open a PR and land it

Invoking this skill on a bean is the request to land it; the user review in Step 6 is the human gate, so you do not need to ask again before opening the PR.

1. Push the branch and open a PR back into `master`. Write a real title and body rather than relying on `--fill`, and end the body with the repo's PR trailer convention:

   ```bash
   git push -u origin <branch>
   gh pr create --base master --title "<area>: <summary>" --body "$(cat <<'EOF'
   <what changed and why>

   Follow-ups: <ids of any deferred follow-up beans, or "none">

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

2. Enable auto-merge (rebase) with branch cleanup, so the PR rebases onto `master` once required checks pass rather than holding open:

   ```bash
   gh pr merge --auto --rebase --delete-branch
   ```

   If this errors because the required checks aren't registered yet, wait a few seconds and retry — auto-merge only sticks once GitHub has queued the checks.

3. Wait for the merge to actually happen, then confirm it:

   ```bash
   gh pr checks --watch        # blocks until CI resolves; non-zero exit means a check FAILED
   gh pr view --json state,mergedAt --jq '{state, mergedAt}'
   ```

   A non-zero exit from `--watch` is not a reason to abort — it means a check failed. Identify the failure and return to **Step 4 (Implement)** to fix it; if the fix is non-trivial, run the review loop (Steps 5–6) again before pushing. Prefer amending the existing commit(s) for a CI fix over stacking new "fix CI" commits — the rebase merge replays every commit onto `master`, so keep the history clean (amending a pushed commit needs `git push --force-with-lease`). Then let auto-merge retry. If `--watch` succeeds but `state` is still `OPEN` (auto-merge can lag the checks), wait and re-check until `mergedAt` is set. Never force the merge past a red check.

4. Once merged, return to `master` and sync. `--delete-branch` already removed the remote branch; delete the local one too. A rebase-merged branch is replayed with new commit SHAs, so git's safe `-d` would refuse it as "not merged" — use `-D`:

   ```bash
   git checkout master && git fomo
   git branch -D <branch>
   ```

After landing, create follow-up beans for anything deferred (e.g. review Suggestions you chose not to apply) and link them in the PR — in the `Follow-ups:` line of the body when you open it, or as a PR comment if decided later — so the PR and its follow-ups read as one logical group of work.
