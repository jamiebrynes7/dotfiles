---
name: maintaining-project-context
description: Use when completing development phases or branches to identify and update CLAUDE.md or AGENTS.md files that may have become stale - analyzes what changed, determines affected contracts and documentation, and coordinates updates
user-invocable: false
---

# Maintaining Project Context

**REQUIRED SUB-SKILL:** Use writing-claude-md-files for all context file creation and updates — it owns the section structure, the freshness date, and the length budget.

## Core Principle

Context files document contracts and architectural intent. **Update them when contracts change, not when implementation changes.** A changed export, interface, invariant, dependency, or architectural decision needs documenting; a bug fix, a refactor with the same behaviour, or a new test does not. Stale documentation is worse than none.

**Trigger:** end of a development phase or branch, or any work that changed contracts, APIs, or domain structure.

## Format Detection (do this first)

```bash
ls -la AGENTS.md CLAUDE.md 2>/dev/null
```

An `AGENTS.md` at the root means the repo is AGENTS.md-canonical: read the existing file before editing, write content to `AGENTS.md`, and give each one a companion `CLAUDE.md` alongside it containing exactly:

```markdown
Read @./AGENTS.md and treat its contents as if they were in CLAUDE.md
```

Otherwise the repo is CLAUDE.md-canonical — edit `CLAUDE.md` files directly. Either way the content uses our structure (Purpose, Contracts, Dependencies, Invariants, …); the filename is only about cross-platform agent compatibility.

## The Process

Diff against the base — the branch point or the start of the phase:

```bash
git diff --name-only <base-sha> HEAD
git diff <base-sha> HEAD --stat
```

Sort the changes into structural (new or moved directories), contract (changed exports, interfaces, public APIs), behavioural (changed invariants or guarantees), and internal. Only the first three warrant an update.

Then, for each one that does:

1. **Place it at the lowest level where it applies.** Domain-specific contracts belong in that domain's context file, not the root; project-wide patterns belong at the root; a cross-domain dependency touches both.
2. **Read the existing file before editing it**, and verify against the code rather than the diff — do the documented contracts, dependencies, and invariants still hold?
3. **Remove what went stale**, don't only append.
