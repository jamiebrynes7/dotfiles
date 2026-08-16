---
name: writing-claude-md-files
description: Use when creating or updating CLAUDE.md files for projects or subdirectories - covers top-level vs domain-level organization, capturing architectural intent and contracts, and mandatory freshness dates
cc:user-invocable: false
---

# Writing CLAUDE.md Files

**REQUIRED**: Load the writing-claude-directives skill for foundational guidance on token efficiency, compliance techniques, and directive structure.

## Core Principle

CLAUDE.md files bridge Claude's statelessness. They preserve context so humans don't re-explain architectural intent every session.

The whole hierarchy turns on one distinction:

- **Top-level** — HOW to work in this codebase: commands, conventions, structure. "How to work here."
- **Subdirectory** — WHY this piece exists and what it PROMISES: contracts, decisions, invariants. "Why this exists and what it promises."

Claude reads these from the current directory up to the root, so a subdirectory file inherits its parents and should never repeat them. Depth is typically one level (domain), occasionally two (a subdomain like `auth/oauth2`), rarely more.

## Top-Level CLAUDE.md

| Section           | Purpose                               |
| ----------------- | ------------------------------------- |
| Tech Stack        | Framework, language, key dependencies |
| Commands          | Build, test, run commands             |
| Project Structure | Directory overview with purposes      |
| Conventions       | Naming, patterns used project-wide    |
| Boundaries        | What Claude can/cannot edit           |

Leave out code style rules (that's what linters are for), exhaustive command lists (reference `package.json` or the justfile), anything that belongs in a domain file, and secrets.

## Subdirectory CLAUDE.md (Domain-Level)

The code already shows WHAT. These files explain intent.

| Section       | Purpose                                   |
| ------------- | ----------------------------------------- |
| Purpose       | WHY this domain exists (not what it does) |
| Contracts     | What this domain PROMISES to others       |
| Dependencies  | What it uses, what uses it, boundaries    |
| Key Decisions | ADR-lite: decisions and rationale         |
| Invariants    | Things that must ALWAYS be true           |
| Key Files     | Entry points worth knowing about          |
| Gotchas       | Non-obvious traps                         |

A domain file earns its place when the domain has non-obvious contracts with other parts, when architectural decisions constrain how the code should evolve, when invariants exist that the code doesn't make obvious, or when new sessions keep needing the same context re-explained. Skip it for trivial utility folders, for implementation details that churn, and for anything better said in a code comment.

### Example

```markdown
# Auth Domain

Last verified: 2025-12-17

## Purpose

Verifies user identity exactly once at the system edge; downstream
services trust the token without re-validating.

## Contracts

- **Exposes**: `validateToken(token) → User | null`, `createSession(credentials) → Token`
- **Guarantees**: Tokens expire after 24h. User objects always include roles.
- **Expects**: Valid JWT format. Database connection available.

## Dependencies

- **Uses**: Database (users table), Redis (session cache)
- **Used by**: All API routes, billing (user identity only)
- **Boundary**: Do NOT import from billing or notifications

## Key Decisions

- JWT over session cookies: stateless auth for horizontal scaling

## Invariants

- Deleted users are soft-deleted (`is_deleted`), never hard deleted

## Gotchas

- Token validation returns null on invalid — it doesn't throw
```

Note what the Purpose section does *not* say: "handles authentication." That is recoverable from the directory name. "Verified exactly once at the edge, downstream trusts the token" is not.

## Freshness Dates: MANDATORY

Every CLAUDE.md MUST carry a `Last verified:` date, because a stale one is worse than none — the date is what tells a reader when the contracts were last confirmed.

**Get the real date from Bash. Do NOT write one from memory:**

```bash
date +%Y-%m-%d
```

## Referencing Files

Name key files plainly (`service.ts - main implementation`). **Do NOT use `@` syntax** (`@./service.ts`) — it force-loads the file into context on every read of the CLAUDE.md, burning tokens whether or not anyone needed it.

## Updating

1. Update the freshness date from `date +%Y-%m-%d`
2. Verify the contracts still hold — read the code, don't trust the diff
3. Remove stale content; short and accurate beats long and wrong
4. Stay within budget: <300 lines top-level, <100 lines subdirectory
