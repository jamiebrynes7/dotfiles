# Plan Self-Review Checklist

Run this against the plan output (markdown file or beans tree) before declaring
the plan ready.

## What to Check

| Category | What to Look For |
|----------|------------------|
| Completeness | TODOs, placeholders, incomplete tasks, missing steps |
| Spec Alignment | Plan covers each spec requirement; no major scope creep |
| Task Decomposition | Tasks have clear boundaries; steps are actionable; bite-sized (2-5 min each) |
| Buildability | Could an engineer follow this without getting stuck? Exact paths, commands, code shown? |
| Type consistency | Function names, signatures, properties match across tasks (no `clearLayers` in one task and `clearFullLayers` in another) |

## Calibration

**Only flag issues that would cause real problems during implementation.**
An implementer building the wrong thing or getting stuck is an issue. Minor
wording, stylistic preferences, and "nice to have" suggestions are not.

## Beans Mode

When the plan is a beans tree, the review surface is the union of bean bodies.
Fetch them in one shot:

```bash
beans query --json '{ bean(id: "<epic-id>") { title body children { id title body children { id title body } } } }'
```

Walk the tree and apply the checklist. Fix issues with `beans update --body-replace-old/--body-replace-new`.

## Markdown Mode

Read the plan file end-to-end. Fix issues inline.

## No Re-Review

Fix and move on. Self-review is one pass — don't loop on your own output.
