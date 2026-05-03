---
# dotfiles-1x96
title: Fork superpowers brainstorming + writing-plans skills with plannotator and beans integration
status: completed
type: feature
priority: normal
created_at: 2026-05-03T13:21:28Z
updated_at: 2026-05-03T13:25:05Z
---

Add forks of the superpowers brainstorming and writing-plans skills under home/lib/ai/skills/, modified so that:

- brainstorming uses 'plannotator annotate --gate --json' for option review and final-spec review (no inline fallback)
- writing-plans emits a beans hierarchy (epic -> feature -> task with bite-sized TDD steps in bodies) when 'beans' is on PATH; falls back to upstream's markdown plan otherwise

Plan file: /home/jamiebrynes/.claude/plans/look-at-superpowers-i-adaptive-kitten.md

## Todo

- [x] Create home/lib/ai/skills/brainstorming/SKILL.md
- [x] Create home/lib/ai/skills/brainstorming/references/spec-reviewer-prompt.md
- [x] Create home/lib/ai/skills/brainstorming/LICENSE
- [x] Create home/lib/ai/skills/writing-plans/SKILL.md
- [x] Create home/lib/ai/skills/writing-plans/references/plan-reviewer-prompt.md
- [x] Create home/lib/ai/skills/writing-plans/LICENSE
- [x] Run nix flake check to verify
- [x] Verify process-frontmatter strips cc:allowed-tools key correctly

## Summary of Changes

Forked two superpowers skills into `home/lib/ai/skills/` so they deploy to both Claude Code and Cursor through the existing `mkSkillFiles` pipeline:

- **brainstorming/** — preserves the upstream HARD-GATE design-first flow but replaces inline option/spec questioning with two `plannotator annotate --gate --json` gates (options review and final-spec review). Each gate parses the JSON `decision` and handles `approved` / `annotated` / `dismissed` without falling back to inline. Visual companion subsystem (Node WebSocket server + HTML frame) was dropped.
- **writing-plans/** — keeps upstream's bite-sized TDD task decomposition, but at start of run probes for the `beans` CLI. If present, emits an epic → feature → task hierarchy with the upstream Task Body Template living in each task bean's body (and `--blocked-by` for spec-declared ordering dependencies). Otherwise falls back to the markdown plan at `docs/specs/plans/`. Subagent-driven-development / executing-plans handoff prompts removed since the beans tree (or markdown file) is the handoff.

Both skills carry `LICENSE` files preserving the upstream MIT notice plus a derivative-work attribution. `references/spec-reviewer-prompt.md` and `references/plan-reviewer-prompt.md` are loaded on-demand for the self-review passes.

Verification: `nix flake check` passes; `process-frontmatter` correctly strips `cc:allowed-tools` for the `cc` variant and drops it entirely for `cursor`.
