---
# dotfiles-cs7q
title: Refactor brainstorming around grilling-style question rounds
status: todo
type: task
created_at: 2026-10-07T15:47:42Z
updated_at: 2026-10-07T15:47:42Z
---

Rework `home/lib/ai/skills/brainstorming/SKILL.md` so design decisions are settled once, through rounds of questions, rather than three times across separate passes (one-at-a-time questions → plannotator options doc → section-by-section chat walkthrough, then plannotator again on the spec).

Inspired by mattpocock's `grilling` skill (https://github.com/mattpocock/skills/blob/main/skills/productivity/grilling/SKILL.md). We're folding its approach into brainstorming rather than adopting it as a separate skill, which would compete with brainstorming for the same trigger.

## Target flow

explore context → question rounds (any approach fork included) → write spec → self-review → plannotator spec review → `writing-plans`

## Todo

- [ ] Replace "ask clarifying questions one at a time" with question rounds:
  - Track decisions as a tree: each decision leads to the decisions that depend on it.
  - Each round, ask every question that can be answered now as a numbered batch. Hold back any question whose answer depends on another question still open.
  - Give every question a recommended answer, worded so that "yes" accepts it.
  - Looking up facts is the agent's job: dispatch a subagent and keep asking the questions that don't depend on that lookup. Decisions are the user's.
  - Questioning is done when no open decisions remain and nothing is silently assumed.
- [ ] Remove the plannotator options doc step and its whole options-review section. A real fork in approach becomes a question in the rounds, with its options, the trade-offs and a recommended answer. With no real fork, there's no question.
- [ ] Remove the section-by-section chat walkthrough. Write the spec straight from the settled decisions, and move the "architecture, components, data flow, error handling, testing seams" coverage into the spec-writing step as a checklist. **Open decision:** the user hasn't yet confirmed they're fine losing the walkthrough (their first full view of the design would then be the spec in plannotator). Confirm before doing this item.
- [ ] Trim the repeated gating language: the HARD-GATE, the "too simple to need a design" section and the two "Do NOT invoke any other implementation skill" lines. State the gate once, with its reason.
- [ ] Probably cut "Design for isolation and clarity": it's generic design advice that overlaps `coding-effectively` and doesn't push against anything Claude does by default.
- [ ] Update the skill's description and checklist to match the new flow; check `writing-plans` still lines up with how brainstorming hands off.

## Notes

- Leave the leftover `docs/specs/*-options.md` files alone. Specs are point-in-time records, and `docs/specs/2026-05-10-beansd-workspace-split.md` links to its options doc by path.
- Keep the main file under the ~150-line budget from `writing-claude-directives`.
