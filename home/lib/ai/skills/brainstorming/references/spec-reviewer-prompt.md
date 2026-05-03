# Spec Self-Review Checklist

Run this against the spec document with fresh eyes before requesting plannotator review.

## What to Check

| Category | What to Look For |
|----------|------------------|
| Completeness | TODOs, placeholders, "TBD", incomplete sections |
| Consistency | Internal contradictions, conflicting requirements |
| Clarity | Requirements ambiguous enough to cause someone to build the wrong thing |
| Scope | Focused enough for a single plan — not covering multiple independent subsystems |
| YAGNI | Unrequested features, over-engineering |

## Calibration

**Only flag issues that would cause real problems during implementation planning.**
A missing section, a contradiction, or a requirement so ambiguous it could be
interpreted two different ways — those are issues. Minor wording improvements
and stylistic preferences are not.

If the spec is sound, proceed to plannotator review without further changes.

## Fix Inline

This is a self-review, not a subagent dispatch. Fix any issues you find directly
in the spec document, then move on. No need to re-review your own fixes.

## Hand-off

Once the self-review pass is clean, invoke `plannotator annotate --gate --json`
on the spec file. The user's annotations are the next gate, not this checklist.
