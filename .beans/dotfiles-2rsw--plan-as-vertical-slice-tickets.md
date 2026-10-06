---
# dotfiles-2rsw
title: Plan as vertical-slice tickets
status: completed
type: task
priority: normal
created_at: 2026-10-06T17:48:39Z
updated_at: 2026-10-06T18:09:33Z
---

## Context

The planning skill currently decomposes a spec into an epic → feature → task tree in which every task bean carries 2–5 minute steps with the full implementation code inline, written for an implementer assumed to have "zero context and questionable taste". In practice this produces beans hundreds of lines long that are pasteable code: they go stale as sibling beans land (beans end up hedging about what may already exist), the planner effectively writes the implementation twice, and the feature layer slices work by component — horizontally — rather than by deliverable behaviour.

The aihero.dev / Matt Pocock model (`to-spec`, `to-tickets` in https://github.com/mattpocock/skills) splits this into two artifacts:

- **Spec** — records decisions (modules, interfaces, contracts, testing seams, out of scope), not file paths or code.
- **Ticket** — a tracer-bullet vertical slice: what to build (end-to-end behaviour), acceptance criteria that fail at the starting commit, and blocking edges. Sized to one fresh context window. The breakdown is reviewed by the user before any ticket is created. The implementer decides *how* when it picks the ticket up.

## Decisions

- Rewrite the existing planning skill in place rather than adding a second one.
- Hierarchy is epic → task; drop the feature layer.
- The implementer skill stays one ticket per run (no parallel orchestration).

## What to build

The brainstorm → spec → plan flow emits vertical-slice tickets described by behaviour and acceptance criteria, gated by a user review of the breakdown; and the implementer works a single ticket from its spec pointer and acceptance criteria, exploring the code and working test-first itself.

## Acceptance criteria

- [x] Planning a spec produces an epic with task tickets whose bodies contain no code or file paths (decision-encoding snippets excepted)
- [x] A plannotator breakdown gate runs before any beans are created
- [x] The implementer skill validates and implements a ticket written in the new shape, deciding the *how* itself
- [x] The brainstorming handoff and spec guidance match the new model
- [x] `nix flake check` passes

## Dry-run notes

Dry run against the paseo-plugins spec (markdown mode, breakdown gate skipped) produced 2 tickets with Phase 1 recorded as already done, versus 8 features / 10 tasks under the old skill. Its friction points were folded back into the skill: compare spec against current code and record already-done work; surface spec gaps as a precondition/question instead of inventing answers; a Constraints section for must-stay-true guards; a carve-out for document pointers and spec-defined names; markdown-mode heading placement; one self-review checklist.

## Spec model

Specs are now explicitly point-in-time decision records: brainstorming adds a Date/Supersedes header and writes superseding specs instead of editing old ones; writing-plans and task-implementer treat code as the source of truth when a spec drifts; root CLAUDE.md documents the convention.

## Summary of Changes

- writing-plans rewritten around tracer-bullet vertical-slice tickets (epic → task, no feature layer): what to build, failable acceptance criteria, constraints, blocking edges; no inline code, paths, or step lists; compares spec against current code and records already-done work; plannotator gate on the breakdown before any beans are created. Reviewer checklist realigned.
- task-implementer reads the referenced spec, validates that criteria can fail, explores and works test-first against the named seam, checks off criteria; one branch per ticket; legacy step-list beans still handled.
- brainstorming: testing seams in the design, decisions-not-layouts guidance, and specs made explicitly point-in-time (Date/Supersedes header; supersede rather than edit). Root CLAUDE.md documents the convention.
- Verified by `nix flake check` and a markdown-mode dry run against the paseo-plugins spec (2 tickets vs. 8 features / 10 tasks previously).
- The breakdown gate and task-implementer on a new-shape ticket were accepted without a live run; revisit if either misbehaves on first real use.
