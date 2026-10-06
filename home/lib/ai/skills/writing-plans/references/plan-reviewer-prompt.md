# Plan Self-Review Checklist

Run this against the plan output (markdown file or beans tree) before declaring
the plan ready.

## What to Check

| Category | What to Look For |
|----------|------------------|
| Spec alignment | Every spec requirement maps to a ticket or to the **Already done** line; no major scope creep; open questions surfaced, not guessed |
| Vertical slicing | Each ticket delivers a demoable behaviour, not one layer ("options added", "package builds") |
| Criteria can fail | Each acceptance criterion is observable and false at the starting commit; none depends on another ticket's work. Must-stay-true guards belong under Constraints, not criteria |
| Context-sized | Each ticket fits one fresh context window; nothing is so small it can only be verified alongside another ticket |
| Real edges | `blocked-by` edges reflect genuine gating, not list order; prefactors come first |
| No stale-prone detail | No implementation code, file paths, line numbers, or step lists — only labelled decision snippets |

## Calibration

**Only flag issues that would cause real problems during implementation.**
An implementer building the wrong thing, being unable to tell when it is done,
or waiting on an edge that isn't real is an issue. Minor wording, stylistic
preferences, and "nice to have" suggestions are not.

## Beans Mode

The review surface is the epic plus its children. Fetch them in one shot:

```bash
beans query --json '{ bean(id: "<epic-id>") { title body children { id title body blockedBy { id title } } } }'
```

Walk the tickets and apply the checklist. Fix issues with `beans update --body-replace-old/--body-replace-new`.

## Markdown Mode

Read the plan file end-to-end. Fix issues inline.

## No Re-Review

Fix and move on. Self-review is one pass — don't loop on your own output.
