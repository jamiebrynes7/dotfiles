---
name: coding-effectively
description: Always use this skill when writing or refactoring code. Covers general code design, error handling, file organization, and code style patterns.
cc:user-invocable: false
---

# Coding Effectively

## Core Engineering Principles

### Explicit over Implicit

- Clear function names over clever abstractions
- Obvious data flow over hidden magic
- Direct dependencies over unnecessary indirection

### Correctness Over Convenience

Model the full error space. No shortcuts.

- Handle all edge cases: race conditions, timing issues, partial failures
- Use the type system to encode correctness constraints
- Prefer compile-time guarantees over runtime checks where possible
- When uncertain, explore and iterate rather than assume

### Error Handling Philosophy

Errors should never be swallowed. When handling errors there are multiple options:

- recoverable locally - error handled
- unrecoverable locally - pass up the stack
- non-critical error - log the error or increment metrics, or both

But you should never swallow errors unhandled.

**Two-tier model:**

1. **User-facing errors**: Semantic exit codes, rich diagnostics, actionable messages
2. **Internal errors**: Programming errors that may panic or use internal types

**Error message format:** Lowercase sentence fragments for "failed to {message}".

```
Good: failed to connect to database: connection refused
Bad:  Failed to Connect to Database: Connection Refused

Good: invalid configuration: missing required field 'apiKey'
Bad:  Invalid Configuration: Missing Required Field 'apiKey'
```

Lowercase fragments compose naturally: `"operation failed: " + error.message` reads correctly.

### Pragmatic Incrementalism

- Prefer specific, composable logic over abstract frameworks
- Evolve design incrementally rather than perfect upfront architecture
- Don't build for hypothetical future requirements
- Document design decisions and trade-offs when making non-obvious choices

**The rule of three applies to abstraction:** Don't abstract until you've seen the pattern three times. Three similar lines of code is better than a premature abstraction.

## File Organization

### Descriptive File Names Over Catch-All Files

Name files by what they contain, not by generic categories.

**Don't create:**

- `utils.ts` - Becomes a dumping ground for unrelated functions
- `helpers.ts` - Same problem
- `common.ts` - What isn't common?
- `misc.ts` - Actively unhelpful

**Do create:**

- `string-formatting.ts` - String manipulation utilities
- `date-arithmetic.ts` - Date calculations
- `api-error-handling.ts` - API error utilities
- `user-validation.ts` - User input validation

**Why this matters:**

- Discoverability: Developers find code by scanning file names
- Cohesion: Related code stays together
- Prevents bloat: Hard to add unrelated code to `string-formatting.ts`
- Import clarity: `import { formatDate } from './date-arithmetic'` is self-documenting

**When you're tempted to create utils.ts:** Stop. Ask what the functions have in common. Name the file after that commonality.

### Module Organization

- Keep module boundaries strict with restricted visibility
- Platform-specific code in separate files: `unix.ts`, `windows.ts`, `posix.ts`
- Use conditional compilation or runtime checks for platform branching
- Test helpers in dedicated modules/files, not mixed with production code
- Prefer many small files over few large ones

## Code style

### Functions should be small and focused

Small and focused functions promote cohesion and testability. If you find a function does more than one thing conceptually, or you are tempted to put 'And' in the name of the function: it does too much.

### Declare close to usage

- Declare identifiers in files that need them. Only export or make public if necessary.
- Within a function, declare variables as close to their usage as possible.
- Limit assignment scope: reassigning and shadowing variables can lead to subtle bugs.

### Flow control

Always keep the happy path left-aligned, avoid deeply nested if-blocks. This harms readability and makes it harder to modify.

**Don't**:

```ts
const possibleValues = getPossibleValues();
const value = getSelected();
if (value !== null) {
  if (possibleValues.contains(value)) {
    return value;
  }

  return null;
}

return null;
```

**Do**:

```ts
const possibleValues = getPossibleValues();
const value = getSelected();

if (value === null) {
  return null;
}

if (!possibleValues.contains(value)) {
  return null;
}

return value;
```

### Code comments

- Comments should communicate purpose and intention, not merely be a description of what the code does.
- Consider the perspective of a future reader: **why** is far more important than **what**. The 'what' can be determined by reading the code.
- Obvious comments should be omitted entirely.
- Avoid comments that are likely to churn if the code structure is changed.

## Property-Driven Design

When designing features, think about properties upfront. This surfaces design gaps early.

**Discovery questions:**

| Question                               | Property Type  | Example                        |
| -------------------------------------- | -------------- | ------------------------------ |
| Does it have an inverse operation?     | Roundtrip      | `decode(encode(x)) == x`       |
| Is applying it twice the same as once? | Idempotence    | `f(f(x)) == f(x)`              |
| What quantities are preserved?         | Invariants     | Length, sum, count unchanged   |
| Is order of arguments irrelevant?      | Commutativity  | `f(a, b) == f(b, a)`           |
| Can operations be regrouped?           | Associativity  | `f(f(a,b), c) == f(a, f(b,c))` |
| Is there a neutral element?            | Identity       | `f(x, 0) == x`                 |
| Is there a reference implementation?   | Oracle         | `new(x) == old(x)`             |
| Can output be easily verified?         | Easy to verify | `is_sorted(sort(x))`           |

**Common design questions these reveal:**

- "What about deleted/deactivated entities?"
- "Case-sensitive or not?"
- "Stable sort or not? Tie-breaking rules?"
- "Which algorithm? Configurable?"

Surface these during design, not during debugging.

## Red Flags

**Stop and refactor when you see:**

- That you are adding to `utils` or `helpers` file
- Error handling that swallows errors or uses generic messages
- Abstractions created for single use cases
- Type assertions (`as any`) to bypass the type system
