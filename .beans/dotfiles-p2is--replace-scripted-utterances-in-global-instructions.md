---
# dotfiles-p2is
title: Replace scripted utterances in global-instructions
status: todo
type: task
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-15T15:33:00Z
parent: dotfiles-nj63
---

**File:** `home/lib/ai/global-instructions.md` (18 → ~8 lines)

Deployed verbatim to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` — highest blast radius in the repo, and effects land outside it.

The preferences are fine; "research before implementing" counteracts a real default. The problem is that all three are *scripted utterances* rather than rules:

- [ ] `Start every feature with: "Let me research the codebase and create a plan before implementing."` — forced preamble even on one-line changes
- [ ] `When uncertain: "Let me ultrathink about this architecture."` — a 4.x thinking-budget trigger phrase, not a behaviour
- [ ] `When choosing: "I see approach A (simple) vs B (flexible). Which do you prefer?"` — scripted sentence for an intent already covered by default behaviour

- [ ] Rewrite as three lines of intent: research before multi-step work; ask when two approaches genuinely diverge; prefer the simple solution when stuck
- [ ] Resolve the overlap with `brainstorming`s HARD-GATE, which mandates a stricter version of the same flow — one of them should own it
- [ ] Keep it assistant-agnostic (it ships to Codex too)
