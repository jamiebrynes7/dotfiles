# AI Assistant Library

Single source of truth for AI assistant skills, deployed via home-manager to Claude Code, Cursor, and Codex, plus the MCP server option types shared by Claude Code and Cursor.

Freshness: 2026-09-23

## Purpose

Provide shared skills that work across AI assistants. A single markdown file can carry variant-specific YAML frontmatter keys (prefixed `cc:`, `cursor:`, or `codex:`), and `process-frontmatter` strips the irrelevant ones at build time.

## Structure

```
global-instructions.md  # Assistant-agnostic global instructions, deployed verbatim to
                         # ~/.claude/CLAUDE.md (claude-code) and ~/.codex/AGENTS.md (codex)
skills/            # Skill subdirectories, each containing SKILL.md + optional supporting files
  default.nix      # mkSkillFiles { variant, targetDir, skillsDirs, recursive ? true } -> { files, conflicts }
mcp/
  default.nix      # Shared MCP server options: mkServerType, mkCommonEntry, enabledServers, mkServerAssertions
tools/
  process-frontmatter/  # Python script: filters YAML frontmatter by variant
```

## Contracts

- `mkSkillFiles` accepts `{ variant, targetDir, skillsDirs, recursive ? true }` where `skillsDirs` is a list of paths. The built-in skills directory is exported as `builtinSkillsDir` and must be included by consumers. `recursive` controls the `home.file` install shape: the default `true` recreates the directory tree with symlinked files; `false` symlinks the skill directory itself. Codex requires `recursive = false` because it ignores symlinked `SKILL.md` files but follows symlinked skill directories.
- Returns `{ files, conflicts }` where `files` is an attrset for `home.file` and `conflicts` is a list of colliding names (detected across all provided directories).
- Consumers (e.g. `home/programs/claude-code/default.nix`, `home/programs/cursor/default.nix`, `home/programs/codex.nix`) use NixOS assertions to fail evaluation when conflicts are non-empty. Codex reads skills from `~/.codex/skills/<name>/SKILL.md` (its native skills directory), so its consumer uses `variant = "codex"` and `targetDir = ".codex/skills"`.

- `mcp/` holds only the MCP server fields every assistant understands (`enable`, `command`, `args`, `env`, `url`, `headers`). Consumers build their option type with `mkServerType [ extraModules ]`, render their own JSON on top of `mkCommonEntry`, and add `mkServerAssertions "<module>" servers` to `assertions`. Cursor (`home/programs/cursor/mcp-types.nix`) adds `envFile` and `auth`; Claude Code adds nothing and marks remote servers `type = "http"`.

## Key Decisions

- **Single-source with variant filtering** — one file per skill, not one per assistant.
- **Skills are directory-list-based** — `mkSkillFiles` takes a flat list of skill directories (including the built-in one). Sub-modules can append their own skill directories via the NixOS module system.
- **Conflict detection via Nix assertions** — catches name collisions across all skill directories at eval time, not at activation.
- **Assistant-specific MCP fields stay in the assistant's module** — a field one assistant can't honour isn't declared for it at all, so setting it fails with Nix's own "option does not exist" error rather than a custom assertion or a silent drop.

## Invariants

- Skills are **subdirectories** of `skills/` containing a `SKILL.md`. Loose files in `skills/` are ignored.
- Variant prefix filtering preserves unprefixed keys for all variants.

## Gotchas

- A skill may only reference files inside its own skill directory. `mkSkillFiles` installs each skill into `.claude/skills`, `.cursor/skills` and `.codex/skills` on every machine this flake is applied to, and skills run against arbitrary projects — so a path like `crates/CLAUDE.md` resolves nowhere but here. Ship references under the skill's own `references/` or `scripts/`.
- Skills require a subdirectory structure — a lone `.md` file in `skills/` won't be discovered.
- `default.nix` files here use `import` (plain function calls), not `imports` — this is library code, not a NixOS module.
- The `tools/` derivation needs `pkgs` passed in; it is not wired through the module system.
