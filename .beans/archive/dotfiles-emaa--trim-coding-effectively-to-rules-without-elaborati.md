---
# dotfiles-emaa
title: Trim coding-effectively to rules without elaboration
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:32:59Z
updated_at: 2026-08-15T16:36:58Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-vmit
---

**File:** `home/lib/ai/skills/coding-effectively/SKILL.md` (191 → ~60 lines, plus a ~25-line reference)

`description: Always use this skill when writing or refactoring code` makes this a second system prompt, so cost pressure is highest here. The reduction comes almost entirely from cutting elaboration, **not** from deleting rules.

Keep as one-liners (taste — nothing else tells the model our position):

- [x] Descriptive filenames over `utils.ts`/`helpers.ts`; rule of three before abstracting; declare close to usage; limit shadowing and reassignment; strict module boundaries; platform-specific code in separate files; lowercase `failed to X` error format

Keep (counteracts a default):

- [x] **Correctness Over Convenience** (17–24) — happy-path bias is a real model tendency
- [x] Error-handling trichotomy (26–34) — recoverable / pass up / log-and-metric, never swallow

Cut elaboration, keep the rule:

- [x] Flow control (111–146) — keep the one-line rule, cut the 30-line before/after TypeScript pair (~35 lines saved)
- [x] Descriptive filenames (64–89) — cut the four-bullet "why this matters" and the eight-item do/dont list; two examples each
- [x] Error format (41–51) — keep the two-line example pair, cut the surrounding explanation

Cut outright:

- [x] Explicit over Implicit (9–15) — does not discriminate any actual decision
- [x] Red Flags (184–191) — restates four rules from above it
- [x] Functions should be small and focused (101–103) — consensus, restates a default

Demote:

- [x] Property-Driven Design (158–182) → `references/property-driven-design.md`. Not a model default so it earns its place, but it is an occasional design technique, not an every-task rule

- [x] Run `nix flake check`

## Summary of Changes

`coding-effectively/SKILL.md`: 185 → 56 lines, plus a new 23-line `references/property-driven-design.md`.

Every rule on the keep list survives. The reduction is elaboration: the 30-line before/after TypeScript flow-control pair, the four-bullet "why this matters" under filenames, and the do/don't lists. Flow control actually gained — the original demonstrated early-return only inside the code sample, so "return early instead of nesting" is now stated outright.

**Three rules were lost and restored.** Subagent review caught that the authorized "Red Flags" cut took two unique rules with it: the prohibition on bypassing the type system (`as any`, unchecked casts) appeared nowhere else in the entire skill library, and "no generic error messages" was gone — `throw new Error("something went wrong")` passed every remaining rule in the file. Separately, the platform-branching mechanism (conditional compilation or a runtime check) was dropped while the rule about *where* platform code lives was kept, leaving the reader told to split `unix.ts`/`windows.ts` with no guidance on dispatch. All three restored by folding into existing lines, at no net line cost.

Also from review: restored the open-ended framing of the edge-case list (a compression had turned three examples into a closed set, on one of the two paragraphs specifically justified as counteracting happy-path bias); strengthened the reference pointer from "see X" to "Before implementing a feature, read X", since the weaker verb sat 20 lines from a `**REQUIRED**: Load` and read as optional by comparison; and cut a property-based-testing line I had added to the reference, which was scope creep in a trim.

`nix flake check` passes. User review returned no changes.
