---
name: coding-effectively
description: Always use this skill when writing or refactoring code. Covers general code design, error handling, file organization, and code style patterns.
cc:user-invocable: false
---

# Coding Effectively

## Correctness over convenience

Model the full error space, not the path you had in mind. Handle every edge case — race conditions, timing issues, partial failures. Encode constraints in the type system, and prefer compile-time guarantees to runtime checks. Never bypass the type system to silence a compiler error (`as any`, unchecked casts). When uncertain, explore and iterate rather than assume.

## Error handling

Never swallow an error. Every error is one of three things:

- **Recoverable locally** — handle it
- **Unrecoverable locally** — pass it up the stack
- **Non-critical** — log it, increment a metric, or both

Two tiers: user-facing errors get semantic exit codes, rich diagnostics, and actionable messages. Internal errors are programming errors, and may panic or use internal types. Never emit a generic message where the specific cause is known.

**Message format** — lowercase sentence fragments, so that `"operation failed: " + error.message` composes:

```
Good: failed to connect to database: connection refused
Bad:  Failed to Connect to Database: Connection Refused
```

## Design

- Don't abstract until you have seen the pattern three times. Three similar lines beat a premature abstraction.
- Prefer specific, composable logic over abstract frameworks.
- Evolve the design incrementally rather than perfecting it upfront, and don't build for hypothetical future requirements.
- Document the trade-off when making a non-obvious choice.

Before implementing a feature, read `references/property-driven-design.md`. Property questions surface design gaps — deleted entities, case sensitivity, tie-breaking — during design rather than during debugging.

## File organization

- Name files for what they contain, never a generic category: `string-formatting.ts`, `date-arithmetic.ts`, `user-validation.ts`, not `utils.ts` or `helpers.ts`. When tempted to create one of those, ask what the functions have in common and name the file after that.
- Keep module boundaries strict, with restricted visibility.
- Platform-specific code goes in its own file: `unix.ts`, `windows.ts`, `posix.ts`, selected by conditional compilation or a runtime check.
- Test helpers belong in dedicated modules, not mixed into production code.
- Prefer many small files to a few large ones.

## Style

- Keep the happy path left-aligned. Return early instead of nesting.
- Declare identifiers in the files that need them; export or make public only when something else needs them.
- Declare variables close to their usage.
- Limit assignment scope — reassignment and shadowing cause subtle bugs.

## Code comments

**REQUIRED**: Load the 'house-style-code-comments' skill for the comment policy.
