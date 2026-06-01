---
# dotfiles-grgy
title: Wire shared AI skills into codex
status: completed
type: feature
priority: normal
created_at: 2026-06-01T13:11:07Z
updated_at: 2026-06-01T13:34:15Z
---

Deploy the shared AI skills library (`home/lib/ai/`) into the Codex CLI, the way it is already wired for Claude Code and Cursor. Follow-up to the codex package work (dotfiles-cdza).

## Context

`home/lib/ai/` is a single-source skills library. Each skill is a `skills/<name>/SKILL.md`; YAML frontmatter can carry variant-prefixed keys (`cc:`, `cursor:`) that `tools/process-frontmatter` strips per variant at build time. `mkSkillFiles { variant, targetDir, skillsDirs }` returns `{ files, conflicts }` for `home.file`, and consumers assert `conflicts == []`. See `home/lib/ai/CLAUDE.md`.

Existing consumers to mirror:
- `home/programs/claude-code/default.nix` — `variant = "cc"`, `targetDir = ".claude/skills"`
- `home/programs/cursor/default.nix` — `variant = "cursor"`, `targetDir = ".cursor/skills"`, with a `skillsDirs` option defaulting to `[ aiSkills.builtinSkillsDir ]` and a NixOS assertion on `skills.conflicts`.

The codex package + empty `home/programs/codex.nix` module already exist (dotfiles-cdza); this bean extends that module.

## Key open question (research first)

Codex CLI does NOT have a `.claude/skills`-style directory abstraction. It centers on `~/.codex/` with `AGENTS.md` (instructions) and `~/.codex/prompts/*.md` (custom slash-command prompts), plus `config.toml`. So the first task is to determine HOW Codex should consume our skills, e.g.:
- Map each skill to a `~/.codex/prompts/<name>.md` prompt (slash commands) — closest 1:1, but prompts are thinner than skills.
- Concatenate/reference skills from a managed `AGENTS.md` section.
- Use a newer Codex skills/config mechanism if one exists at the pinned version.

Confirm against the actual Codex version we package (currently 0.135.0) before committing to a format — this decision drives `targetDir` and whether `process-frontmatter` needs a `codex` variant at all.

## Todos

- [ ] Research how Codex CLI (v0.135.0+) loads custom prompts/instructions and decide the deployment target (prompts dir vs AGENTS.md vs other); document the decision
- [ ] Add `"codex"` to `KNOWN_VARIANTS` in `home/lib/ai/tools/process-frontmatter/process-frontmatter.py` and update its docstring/tests
- [x] Decide whether existing skills need `codex:`-prefixed frontmatter overrides: NO — unprefixed name/description suffice; cc: keys are stripped for codex
- [x] Extend `home/programs/codex.nix` to deploy skills via `mkSkillFiles { variant = "codex"; targetDir = ".codex/skills"; skillsDirs; }`, add a `skillsDirs` option defaulting to `[ aiSkills.builtinSkillsDir ]`, and assert `skills.conflicts == []` (mirrors the cursor module)
- [ ] Verify with `nix flake check` and by inspecting the generated files for a sample home configuration
- [x] Update `home/lib/ai/CLAUDE.md` (added codex variant + consumer) and bumped freshness to 2026-06-01

## Research findings (resolves the open question)

- Codex 0.135.0 has a NATIVE skills system mirroring Claude's: skills load from `$CODEX_HOME/skills/<name>/SKILL.md` (`CODEX_HOME` defaults to `~/.codex`). Confirmed via binary: `skills/list` app-server method, `SkillsChangedNotification` watching local skill files, `skills/<name>/SKILL.md` references. => deployment target is `targetDir = ".codex/skills"`; the bean's original premise (no skills-dir abstraction) is outdated.
- SKILL.md frontmatter keys are `name`/`description` — same as Claude. Library skills carry only unprefixed `name`/`description` + `cc:`-prefixed keys (`cc:allowed-tools`, `cc:user-invocable`), which are stripped for the codex variant. => NO `codex:` frontmatter overrides needed initially.
- `process-frontmatter.py` errors on variants outside `KNOWN_VARIANTS`, so `"codex"` must be added there. No test suite exists, so only the docstring is updated.
- Implementation mirrors `home/programs/cursor/default.nix` (skillsDirs option, mkSkillFiles, conflicts assertion).

## Summary of Changes

Wired the shared AI skills library (`home/lib/ai/`) into the Codex CLI, mirroring the existing Cursor consumer.

- `home/programs/codex.nix` — added a `skillsDirs` option (defaulting to `[ aiSkills.builtinSkillsDir ]`) and deploy skills via `mkSkillFiles { variant = "codex"; targetDir = ".codex/skills"; }`, with a `skills.conflicts == []` assertion. Stays default-off, not enabled in any profile.
- `home/lib/ai/tools/process-frontmatter/process-frontmatter.py` — added `"codex"` to `KNOWN_VARIANTS` + docstring.
- `home/lib/ai/skills/default.nix` — docstring lists codex as a valid variant.
- `home/lib/ai/CLAUDE.md` — documented codex as a third variant/consumer; freshness bumped to 2026-06-01.

Research outcome: Codex 0.135.0 has a native skills system reading `~/.codex/skills/<name>/SKILL.md` with `name`/`description` frontmatter (same shape as Claude), so it maps cleanly with no `codex:` overrides — the `cc:` keys are stripped for the codex variant.

Validation: built a home-manager activation package with codex enabled (`~/.codex/skills/<name>/SKILL.md` generated, cc: keys stripped, no leaked prefixes); `nix flake check` exit 0. Subagent + user review passed.

Note: `nix flake check` only builds packages (`checks = self.packages`), so it does NOT exercise home-manager modules — skill-library consumers are unguarded by CI. Possible follow-up: add a home-config build to checks.
