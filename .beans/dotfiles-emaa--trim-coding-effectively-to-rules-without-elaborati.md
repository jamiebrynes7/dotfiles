---
# dotfiles-emaa
title: Trim coding-effectively to rules without elaboration
status: todo
type: task
priority: normal
created_at: 2026-08-15T15:32:59Z
updated_at: 2026-08-15T15:33:10Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-vmit
---

**File:** `home/lib/ai/skills/coding-effectively/SKILL.md` (191 → ~60 lines, plus a ~25-line reference)

`description: Always use this skill when writing or refactoring code` makes this a second system prompt, so cost pressure is highest here. The reduction comes almost entirely from cutting elaboration, **not** from deleting rules.

Keep as one-liners (taste — nothing else tells the model our position):

- [ ] Descriptive filenames over `utils.ts`/`helpers.ts`; rule of three before abstracting; declare close to usage; limit shadowing and reassignment; strict module boundaries; platform-specific code in separate files; lowercase `failed to X` error format

Keep (counteracts a default):

- [ ] **Correctness Over Convenience** (17–24) — happy-path bias is a real model tendency
- [ ] Error-handling trichotomy (26–34) — recoverable / pass up / log-and-metric, never swallow

Cut elaboration, keep the rule:

- [ ] Flow control (111–146) — keep the one-line rule, cut the 30-line before/after TypeScript pair (~35 lines saved)
- [ ] Descriptive filenames (64–89) — cut the four-bullet "why this matters" and the eight-item do/dont list; two examples each
- [ ] Error format (41–51) — keep the two-line example pair, cut the surrounding explanation

Cut outright:

- [ ] Explicit over Implicit (9–15) — does not discriminate any actual decision
- [ ] Red Flags (184–191) — restates four rules from above it
- [ ] Functions should be small and focused (101–103) — consensus, restates a default

Demote:

- [ ] Property-Driven Design (158–182) → `references/property-driven-design.md`. Not a model default so it earns its place, but it is an occasional design technique, not an every-task rule

- [ ] Run `nix flake check`
