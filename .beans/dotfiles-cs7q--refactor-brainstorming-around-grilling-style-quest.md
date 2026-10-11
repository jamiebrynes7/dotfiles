---
# dotfiles-cs7q
title: Refactor brainstorming around grilling-style question rounds
status: completed
type: task
priority: normal
created_at: 2026-10-07T15:47:42Z
updated_at: 2026-10-11T16:25:55Z
---

Rework `home/lib/ai/skills/brainstorming/SKILL.md` so design decisions are settled once, through rounds of questions, rather than three times across separate passes (one-at-a-time questions → plannotator options doc → section-by-section chat walkthrough, then plannotator again on the spec).

Inspired by mattpocock's `grilling` skill (https://github.com/mattpocock/skills/blob/main/skills/productivity/grilling/SKILL.md). We're folding its approach into brainstorming rather than adopting it as a separate skill, which would compete with brainstorming for the same trigger.

## Target flow

explore context → question rounds (any approach fork included) → write spec → self-review → plannotator spec review → `writing-plans`

## Todo

- [x] Replace "ask clarifying questions one at a time" with question rounds:
  - Track decisions as a tree: each decision leads to the decisions that depend on it.
  - Each round, ask every question that can be answered now as a numbered batch. Hold back any question whose answer depends on another question still open.
  - Give every question a recommended answer, worded so that "yes" accepts it.
  - Looking up facts is the agent's job: dispatch a subagent and keep asking the questions that don't depend on that lookup. Decisions are the user's.
  - Questioning is done when no open decisions remain and nothing is silently assumed.
- [x] Remove the plannotator options doc step and its whole options-review section. A real fork in approach becomes a question in the rounds, with its options, the trade-offs and a recommended answer. With no real fork, there's no question.
- [x] Remove the section-by-section chat walkthrough. Write the spec straight from the settled decisions, and move the "architecture, components, data flow, error handling, testing seams" coverage into the spec-writing step as a checklist. Confirmed with the user: drop the walkthrough.
- [x] Trim the repeated gating language: the HARD-GATE, the "too simple to need a design" section and the two "Do NOT invoke any other implementation skill" lines. State the gate once, with its reason.
- [x] Cut (confirmed) "Design for isolation and clarity": it's generic design advice that overlaps `coding-effectively` and doesn't push against anything Claude does by default.
- [x] Update the skill's description and checklist to match the new flow; check `writing-plans` still lines up with how brainstorming hands off.

## Notes

- Leave the leftover `docs/specs/*-options.md` files alone. Specs are point-in-time records, and `docs/specs/2026-05-10-beansd-workspace-split.md` links to its options doc by path.
- Keep the main file under the ~150-line budget from `writing-claude-directives`.

## Summary of Changes

Rewrote `home/lib/ai/skills/brainstorming/SKILL.md` (133 → 101 lines) around grilling-style question rounds: decisions are tracked as a tree and asked as numbered batches with recommended answers; facts are looked up by a subagent while the questions that don't depend on them continue; skipped questions stay open. The plannotator options doc and the section-by-section walkthrough are gone. A fork in approach is now a question, and the spec is written straight from the settled decisions against a coverage checklist (architecture, components, data flow, error handling, testing seams). If the checklist turns up a decision nobody made, that means another round, not a choice made silently in the spec. The gate is stated once and runs through the hand-off to writing-plans. "Design for isolation and clarity" is cut. Plannotator now runs in the background where the shell notifies on exit. LICENSE credits the grilling skill (MIT). writing-plans needed no changes.
