---
name: whats-next
description: Use when the user asks what to work on next ("what's next?", "what should I pick up?", "anything ready?"). Surfaces in-progress and ready beans, grouped by parent with real blocker/container status, recommends a starting point, and hands off to task-implementer on selection.
---

# What's Next

Help the user choose their next piece of work from the bean tracker. The value here is **judgment, not a JSON dump**: resume before you start, group related work, and only surface beans that are genuinely actionable. This skill is read-only with respect to bean state — it surfaces and recommends; `task-implementer` owns status changes.

## Step 1 — Gather state

Pull in-progress and ready work together, with enough relationship context to reason about blockers and containers in one pass:

```bash
beans query --json '{
  inProgress: beans(filter: { status: ["in-progress"] }) {
    id title type priority
    children { id title status }
  }
  ready: beans(filter: { excludeStatus: ["completed", "scrapped", "draft", "in-progress"], isBlocked: false, excludeImplicitTerminal: true }) {
    id title type priority
    parent { id title type status }
    children { id title status }
    blockedBy { id title status }
  }
}'
```

`excludeImplicitTerminal: true` matches `beans list --ready` semantics: it drops beans that inherit a terminal status from a scrapped/completed ancestor (which `excludeStatus` alone would miss, since that bean's *own* status is still `todo`). The plain CLI equivalents (`beans list --json -s in-progress`, `beans list --json --ready`) work too, but the GraphQL query gives you `parent`, `children`, and `blockedBy` statuses in a single call — which the next steps need.

## Step 2 — Resume beats starting

If anything is **in-progress**, present it first and lead with it. A half-finished bean is almost always the right next move over starting something new — finishing reduces work-in-flight. Note any in-progress bean that is a container (has children) so the user knows the real work is in a child.

## Step 3 — Present ready work with judgment

Group ready beans **by parent epic/feature**, not as a flat list. Under each group show `id`, `title`, and `type`. Then apply three checks so the list reflects reality, not raw fields:

- **Real blockers only.** A bean listed under `blockedBy` is only actually blocked if that blocker is *not* `completed`. A blocked-by whose blocker is already done is **not** blocked — surface it as available. (We hit exactly this with `nimbus-ibzl`.) The `isBlocked: false` filter handles the common case, but verify any `blockedBy` you display.
- **Flag containers.** A bean with `children` is usually a container, not something to implement directly — point at its actionable children instead of the container itself.
- **Respect priority.** Order within a group by priority (`critical` → `high` → `normal` → `low` → `deferred`) so the obvious candidate floats up.

## Step 4 — Recommend, then let the user choose

First lay out the candidates in a markdown table so the user can compare at a glance. One row per actionable bean, ordered with your recommended pick at the top. Mark the recommendation with a ⭐ in a leading column so it stands out:

| | Bean | Type | Why |
|---|---|---|---|
| ⭐ | `nimbus-lv0f` — Constant-time bearer `authenticate()` | task | Unblocks `ka11`; closes the last feature in the Foundation epic |
| | `nimbus-xxuw` — Fix deprecation warnings in `cloudflare:test` | task | Standalone housekeeping |

Then call **AskUserQuestion** to capture the selection — it gives the user clickable options instead of forcing them to type a bean id. Use a single question (header `Next bean`), one option per candidate. Put the recommended bean first with `(Recommended)` appended to its label, and use each option's `description` for the one-line rationale. The user can always pick "Other" to name a bean outside the list.

## Step 5 — Hand off

Once the user selects a bean, hand off to the **task-implementer** skill with the chosen bean id. Do not change the bean's status yourself — `task-implementer` validates the bean and sets it in-progress as part of its own loop.
