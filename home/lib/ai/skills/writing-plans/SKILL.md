---
name: writing-plans
description: "Use when you have a spec or requirements for a multi-step task, before touching code. Breaks the spec into tracer-bullet vertical-slice tickets — behaviour, acceptance criteria, and blocking edges, not implementation steps; emits an epic with task children when the beans CLI is available, otherwise a markdown plan."
cc:allowed-tools: Bash(plannotator:*)
---

# Writing Plans

## Overview

Turn an approved spec into a small graph of **tickets**. A ticket describes *what behaviour to deliver and how to tell it is done* — not how to build it. The implementer picks a ticket up cold, with the repo and the spec in front of it, and decides the how at that point, against the code as it is then.

Tickets do not contain implementation code or step lists. Code written at planning time is a guess about the repo's future state; every ticket that lands before it makes the guess worse. Planning effort goes into the spec's decisions and the shape of the breakdown instead.

**Inputs:** a spec (typically at `docs/specs/YYYY-MM-DD-<topic>.md`) plus any constraints raised during brainstorming.

## Output Mode

The first action in this skill is to detect the output mode:

```bash
if command -v beans >/dev/null 2>&1; then mode=beans; else mode=markdown; fi
```

- **beans mode** — an epic whose children are task beans, one per ticket. The default whenever beans is available.
- **markdown mode** — a single plan file at `docs/specs/plans/YYYY-MM-DD-<feature>.md`. Used only when beans is not on `$PATH`.

**Trust the detection — the first bean you create is the epic.** Do not create probe, scratch, or "test" beans to inspect the CLI's output format or confirm it works. Every bean is a durable artifact: it lands in the project's `.beans/` registry, shows up in `beans list`, and has to be scrapped or archived afterwards. If you need a non-destructive sanity check that beans is wired up, run `beans check` — it never creates or modifies beans.

Everything up to the Breakdown Review applies to both modes — only the final emission differs.

## Does This Need Tickets?

If the whole spec can be implemented in one session — one fresh context window, one reviewable diff — do not decompose it. In beans mode, create a single task bean using the Ticket Body Template; in markdown mode, write a single-ticket plan. Then hand off.

If the spec covers multiple independent subsystems, it should have been split during brainstorming. If it wasn't, suggest one plan per subsystem; in beans mode that means one epic per subsystem.

## Drafting Tickets

### Start from the code, not just the spec

A spec is a point-in-time record of decisions, not a description of the current system — where the spec and the code disagree, the code wins. Compare the spec against the current code before slicing. Requirements already satisfied are recorded once in the plan's **Already done** line (with the evidence — a commit, an option, a check) and are not ticketed.

If the breakdown hinges on something the spec leaves open — an undecided behaviour, or a phase gated on something the spec doesn't supply — do not invent the answer, and do not patch the decision into the old spec. New decisions belong in a new spec that supersedes the relevant sections: suggest returning to brainstorming for it. If you cannot ask, record the gap as a **Precondition** on the epic or plan and keep it out of the tickets.

### Prefactor first

Look for refactors that would make the feature straightforward — "make the change easy, then make the easy change". Each becomes its own ticket, ordered ahead of the feature tickets that benefit from it.

### Vertical slices

Each ticket is a **tracer bullet**: a narrow but complete path through every layer the change touches (e.g. option, module, package, check, docs), not one layer across the whole feature.

- A completed ticket is demoable or verifiable on its own. Ask of every ticket: *what can I demo when this is done?* If the answer is a layer ("the options exist", "the package builds") rather than a behaviour, it is a horizontal slice — re-cut it.
- Each ticket fits one fresh context window.
- Each ticket lands independently; nothing waits for a later ticket to make it useful.
- Prefer fewer, meaningful tickets over many atomic ones. Over-decomposition is the most common failure — if two tickets can only be verified together, merge them.

### Wide-refactor exception

A single mechanical change whose blast radius spans the codebase (renaming a shared option, retyping a widely used value) cannot land as a green vertical slice. Sequence it as **expand → migrate → contract**: add the new form beside the old; migrate callers in batches sized by blast radius, each its own ticket blocked by the expand; then delete the old form in a ticket blocked by every batch.

### Blocking edges

Give each ticket the tickets that genuinely gate it. Don't infer ordering from list position — only encode a dependency when the ticket cannot start or cannot be verified without the other. Over-blocking turns the ready set into a serial queue.

## Ticket Body Template

````markdown
**Spec:** `docs/specs/YYYY-MM-DD-<topic>.md` — <section(s) this ticket implements>

## What to build

<The end-to-end behaviour this ticket makes work, from the user's or operator's perspective. Not a layer-by-layer list.>

## Acceptance criteria

- [ ] <Observable criterion — must be false at the commit the implementer starts from>
- [ ] <...>

## Constraints

<Optional. Things that are true today and must stay true — no new import-from-derivation, a helper kept out of a public output. Exempt from the "must be false" rule; the reviewer checks them.>

## Notes

<Optional. Decisions or verified upstream facts this ticket depends on that the spec does not already record.>
````

**No code, no paths.** Ticket bodies do not contain implementation code, file paths, line numbers, or step lists — they go stale as soon as a neighbouring ticket lands. Name modules, options, and behaviours by their domain names instead. Pointers to documents (the spec, a `CLAUDE.md`) are fine, as are names the spec itself defines as concepts (a source tree the spec introduces by its directory name). The one code exception: a snippet that encodes a *decision* more precisely than prose can (a schema, a type shape, an option signature) — inline only the decision-rich part and label it as such.

**Criteria must be able to fail.** Each criterion is something the implementer can observe and that is not already true before the work starts. Watch for three failure shapes: a criterion already satisfied at the base commit, one only another ticket's work can satisfy, and one that restates the request instead of naming an observation. "Handle errors appropriately" is not a criterion; "an unknown plugin id fails evaluation with an assertion naming the id" is.

## Breakdown Review

Before creating any beans or writing the plan file, write the breakdown to a transient file — `docs/specs/YYYY-MM-DD-<topic>-tickets.md` — as a numbered list, one entry per ticket:

```markdown
1. **<Title>** — Blocked by: none
   Delivers: <the behaviour you can demo when it is done>
2. **<Title>** — Blocked by: 1
   Delivers: <...>
```

End the file with the questions the user should weigh: is the granularity right (too coarse, too fine)? Are the blocking edges real? Should any tickets merge or split?

Then invoke:

```bash
plannotator annotate --gate --json docs/specs/YYYY-MM-DD-<topic>-tickets.md
```

Set the Bash tool timeout to `1800000` ms (30 minutes) so the user has enough time to review. The command returns `{"decision": "approved"|"annotated"|"dismissed", "feedback": "..."}`:

- **`approved`** — delete the breakdown file (`rm -f <path>`) and emit the plan below.
- **`annotated`** — treat each annotation block as an instruction: revise the breakdown (merge, split, re-edge, re-slice), then re-run plannotator. Loop until `approved`.
- **`dismissed`** — the user wants a different cut. Re-slice from scratch and re-invoke plannotator.

Nothing is emitted until the breakdown is approved.

## Beans Mode

### 1. Epic

```bash
beans create --json "<feature name>" \
  -t epic \
  -d "$(cat <<'EOF'
**Goal:** <one sentence>

**Spec:** docs/specs/YYYY-MM-DD-<topic>.md

**Testing seam:** <where the behaviour is verified — the existing check, test suite, or harness the tickets extend>

**Already done:** <spec requirements already satisfied, with evidence — omit if none>

**Precondition:** <anything the work is gated on that the spec does not supply — omit if none>
EOF
)" \
  -s todo
```

Capture the returned `id` — this is `<epic-id>`.

### 2. Tickets

Create tickets in dependency order (blockers first) so each one's blocking edges can reference real ids:

```bash
beans create --json "<ticket title>" \
  -t task \
  --parent <epic-id> \
  -d "$(cat <<'EOF'
<Ticket Body Template content>
EOF
)" \
  -s todo
```

Then record each blocking edge from the approved breakdown:

```bash
beans update --json <ticket-id> --blocked-by <blocker-id>
```

### 3. Self-review and handoff

Fetch the tree in one shot and run the Self-Review below:

```bash
beans query --json '{ bean(id: "<epic-id>") { title body children { id title body blockedBy { id title } } } }'
```

Fix issues with `beans update --json <id> --body-replace-old "<exact text>" --body-replace-new "<replacement>"`. Then print the tree and tell the user:

> Plan ready in beans (epic `<epic-id>`). Start with `beans ready`. Each ticket names the behaviour to deliver and its acceptance criteria; the implementer works out the how from the spec and the code.

Stop. The beans tree is the handoff. Do not invoke any other skill.

## Markdown Mode

Write the plan to `docs/specs/plans/YYYY-MM-DD-<feature>.md` (user preferences for plan location override this default):

```markdown
# [Feature Name] Plan

**Goal:** [one sentence]

**Spec:** `docs/specs/YYYY-MM-DD-<topic>.md`

**Testing seam:** [where the behaviour is verified]

**Already done:** [spec requirements already satisfied, with evidence — omit if none]

**Precondition:** [anything the work is gated on that the spec does not supply — omit if none]

---
```

Then one section per ticket, in dependency order: a `### NN: <title>` heading, a `**Blocked by:**` line (ticket numbers, or "none") directly beneath it, then the Ticket Body Template with its `##` headings demoted to `####`.

Run the Self-Review, then point the user at the plan and stop — the plan is the handoff.

## Self-Review

Look at the emitted tickets with fresh eyes against the spec and run the checklist in `references/plan-reviewer-prompt.md`: spec alignment (every requirement is ticketed or recorded as already done), vertical slicing, criteria that can fail, context-sized tickets, real edges, and no stale-prone detail.

Fix issues inline. No need to re-review your own fixes.
