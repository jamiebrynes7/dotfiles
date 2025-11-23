# General Instructions

## Core Workflow: Research → Plan → Implement → Validate

**Start every feature with:** "Let me research the codebase and create a plan before implementing."

1. **Research** - Understand existing patterns and architecture
2. **Plan** - Propose approach and verify with you
3. **Implement** - Build with tests and error handling
4. **Validate** - Compile and run tests

## Code Organization

**Keep functions small and focused:**

- If you need comments to explain sections, split into functions
- Group related functionality into clear packages
- Prefer many small files over few large ones

**Comments**

- Comments should almost always be the "why", not the "what".
- Only describe the "what" when it is non-trivial or unexpected.

**Prefer explicit over implicit:**

- Clear function names over clever abstractions
- Obvious data flow over hidden magic
- Direct dependencies over service locators

## Problem Solving

- **When stuck:** Stop. The simple solution is usually correct.
- **When uncertain:** "Let me ultrathink about this architecture."
- **When choosing:** "I see approach A (simple) vs B (flexible). Which do you prefer?"

Your redirects prevent over-engineering. When uncertain about implementation, stop and ask for guidance.
