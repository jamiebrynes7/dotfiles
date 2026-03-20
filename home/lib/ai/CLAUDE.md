# AI Assistant Library

Single source of truth for AI assistant skills, deployed via home-manager to both Claude Code and Cursor.

Freshness: 2026-03-20

## Purpose

Provide shared skills that work across AI assistants. A single markdown file can carry variant-specific YAML frontmatter keys (prefixed `cc:` or `cursor:`), and `process-frontmatter` strips the irrelevant ones at build time.

## Structure

```
skills/            # Skill subdirectories, each containing SKILL.md + optional supporting files
  default.nix      # mkSkillFiles { variant, targetDir, skillsDirs } -> { files, conflicts }
tools/
  process-frontmatter/  # Python script: filters YAML frontmatter by variant
```

## Contracts

- `mkSkillFiles` accepts `{ variant, targetDir, skillsDirs }` where `skillsDirs` is a list of paths. The built-in skills directory is exported as `builtinSkillsDir` and must be included by consumers.
- Returns `{ files, conflicts }` where `files` is an attrset for `home.file` and `conflicts` is a list of colliding names (detected across all provided directories).
- Consumers (e.g. `home/programs/claude-code/default.nix`, `home/programs/cursor/default.nix`) use NixOS assertions to fail evaluation when conflicts are non-empty.

## Key Decisions

- **Single-source with variant filtering** — one file per skill, not one per assistant.
- **Skills are directory-list-based** — `mkSkillFiles` takes a flat list of skill directories (including the built-in one). Sub-modules can append their own skill directories via the NixOS module system.
- **Conflict detection via Nix assertions** — catches name collisions across all skill directories at eval time, not at activation.

## Invariants

- Skills are **subdirectories** of `skills/` containing a `SKILL.md`. Loose files in `skills/` are ignored.
- Variant prefix filtering preserves unprefixed keys for all variants.

## Gotchas

- Skills require a subdirectory structure — a lone `.md` file in `skills/` won't be discovered.
- `default.nix` files here use `import` (plain function calls), not `imports` — this is library code, not a NixOS module.
- The `tools/` derivation needs `pkgs` passed in; it is not wired through the module system.
