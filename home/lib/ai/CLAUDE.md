# AI Assistant Library

Single source of truth for AI assistant commands and skills, deployed via home-manager to both Claude Code and Cursor.

Freshness: 2026-02-28

## Purpose

Provide shared slash-commands and skills that work across AI assistants. A single markdown file can carry variant-specific YAML frontmatter keys (prefixed `cc:` or `cursor:`), and `process-frontmatter` strips the irrelevant ones at build time.

## Structure

```
commands/          # Slash-command .md files (e.g. /commit, /review)
  default.nix      # mkCommandFiles { variant, targetDir, extraCommandsDir } -> { files, conflicts }
skills/            # Skill subdirectories, each containing SKILL.md + optional supporting files
  default.nix      # mkSkillFiles { variant, targetDir, extraSkillsDir } -> { files, conflicts }
tools/
  process-frontmatter/  # Python script: filters YAML frontmatter by variant
```

## Contracts

- `mkCommandFiles` and `mkSkillFiles` each accept `{ variant, targetDir, extraCommandsDir/extraSkillsDir }`.
- Both return `{ files, conflicts }` where `files` is an attrset for `home.file` and `conflicts` is a list of colliding names.
- Consumers (e.g. `home/programs/claude-code/default.nix`, `home/programs/cursor.nix`) use NixOS assertions to fail evaluation when conflicts are non-empty.

## Key Decisions

- **Single-source with variant filtering** — one file per command/skill, not one per assistant.
- **Extra directories for overrides** — each consumer module can pass an `extraCommandsDir`/`extraSkillsDir` for assistant-specific additions.
- **Conflict detection via Nix assertions** — catches name collisions between built-in and extra files at eval time, not at activation.

## Invariants

- Commands are `.md` files directly in `commands/`.
- Skills are **subdirectories** of `skills/` containing a `SKILL.md`. Loose files in `skills/` are ignored.
- Variant prefix filtering preserves unprefixed keys for all variants.

## Gotchas

- Skills require a subdirectory structure — a lone `.md` file in `skills/` won't be discovered.
- `default.nix` files here use `import` (plain function calls), not `imports` — this is library code, not a NixOS module.
- The `tools/` derivation needs `pkgs` passed in; it is not wired through the module system.
