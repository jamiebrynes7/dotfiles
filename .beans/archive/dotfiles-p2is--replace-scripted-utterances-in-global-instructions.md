---
# dotfiles-p2is
title: Replace scripted utterances in global-instructions
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-16T09:01:16Z
parent: dotfiles-nj63
---

**File:** `home/lib/ai/global-instructions.md` (18 → ~8 lines)

Deployed verbatim to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` — highest blast radius in the repo, and effects land outside it.

The preferences are fine; "research before implementing" counteracts a real default. The problem is that all three are *scripted utterances* rather than rules:

- [x] `Start every feature with: "Let me research the codebase and create a plan before implementing."` — forced preamble even on one-line changes
- [x] `When uncertain: "Let me ultrathink about this architecture."` — a 4.x thinking-budget trigger phrase, not a behaviour
- [x] `When choosing: "I see approach A (simple) vs B (flexible). Which do you prefer?"` — scripted sentence for an intent already covered by default behaviour

- [x] Rewrite as three lines of intent: research before multi-step work; ask when two approaches genuinely diverge; prefer the simple solution when stuck
- [x] Resolve the overlap with `brainstorming`s HARD-GATE, which mandates a stricter version of the same flow — one of them should own it
- [x] Keep it assistant-agnostic (it ships to Codex too)

## Summary of Changes

Rewrote `home/lib/ai/global-instructions.md` (18 → 7 lines) as three rules of intent under a `## Working Style` heading, replacing the `Core Workflow` numbered ritual and the three scripted utterances.

- Dropped the forced "Let me research the codebase..." preamble, the `ultrathink` trigger phrase (4.x thinking-budget artifact), and the scripted "approach A vs B" sentence.
- Kept the intents as behaviour: research before multi-step work (not one-line changes); ask on consequential choices; default to the simplest thing that works.
- **HARD-GATE overlap resolved by ownership** — `brainstorming` keeps the mandated design-approval gate (the audit preserves it as a strategic guardrail), so global-instructions states research as a preference and no longer mandates a competing plan-approval flow.
- Assistant-agnostic: no Claude-specific phrasing, ships cleanly to `~/.codex/AGENTS.md`.

User review caught a conflict between the ask-vs-decide rules (both matched a simple-vs-flexible fork). Split them by consequence instead: ask for choices with durable consequences (data model, interface, new dependency), decide everything else yourself toward the simple option.

The old `Validate — compile and run tests` step was dropped to hold the three-line target; noted as an optional add-back, not taken.
