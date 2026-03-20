---
name: "plannotator:user-code-review"
description: >
  Request a code review from the user via plannotator.
  Use at the end of an implementation task, or when the user asks for a review cycle.
  Collects structured annotations, then addresses each item.
cc:allowed-tools: Bash(plannotator:*)
---

Plannotator provides a structured review UI where the user can leave inline
annotations on specific files and lines. Use it to get precise, actionable feedback.

Run the following command to start a review session. Set the Bash tool timeout
to 1800000ms (30 minutes) so the user has enough time to review and annotate.

```
plannotator review
```

## Reviewing Feedback

For each annotation from the user:

1. **Summarize** the feedback in one line
2. **Evaluate** whether the suggestion is valid — push back if it would introduce a bug, conflict with project conventions, or reduce code quality
3. **Act** — apply the fix or explain why you disagree

If no changes were requested, acknowledge this and move on.
