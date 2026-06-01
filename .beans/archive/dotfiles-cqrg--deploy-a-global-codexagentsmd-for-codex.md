---
# dotfiles-cqrg
title: Deploy a global ~/.codex/AGENTS.md for codex
status: completed
type: feature
priority: normal
created_at: 2026-06-01T14:08:06Z
updated_at: 2026-06-01T15:02:33Z
---

Deploy a global Codex instructions file to `~/.codex/AGENTS.md` via home-manager, mirroring how `claude-code` deploys the global `~/.claude/CLAUDE.md`. Follow-up to the codex package (dotfiles-cdza) and skills wiring (dotfiles-grgy).

## Context

Codex reads global agent instructions from `$CODEX_HOME/AGENTS.md` (`CODEX_HOME` defaults to `~/.codex`) — confirmed from the codex 0.135.0 binary (`_codex_home()` => `~/.codex`; AGENTS.md spec in base instructions). This is the Codex analogue of Claude Code's global `~/.claude/CLAUDE.md`.

How claude-code does it today:
- `home/programs/claude-code/default.nix:151` — `home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;`
- The source is the checked-in `home/programs/claude-code/CLAUDE.md`. Per the repo root `CLAUDE.md` "Boundaries" note, that file IS the global `~/.claude/CLAUDE.md` (it affects every project), so edits there are global-scope.

The codex module (`home/programs/codex.nix`) already sets `home.file = skills.files;`; this would add an `".codex/AGENTS.md".source = ...;` entry alongside it (merge, don't overwrite).

## Key design question (decide before implementing)

The global CLAUDE.md and the global AGENTS.md are both "global agent instructions" and largely overlap in intent. Decide the source-of-truth strategy:
- **Share one file**: point `~/.codex/AGENTS.md` at the existing `home/programs/claude-code/CLAUDE.md` (single source, zero drift). Risk: that file may contain Claude-Code-specific phrasing/features that do not apply to Codex.
- **Separate file**: add a new checked-in `home/programs/codex/AGENTS.md` (or similar) with Codex-tailored content. Risk: two files to keep in sync.
- **Hybrid**: a shared common core + a small codex-specific preamble.

Recommend confirming with the user, since this is a content/maintenance tradeoff, not a purely technical one. Also review the current global CLAUDE.md content for Claude-specific bits before reusing it.

## Todos

- [x] Confirmed empirically: `codex debug prompt-input` injects `$CODEX_HOME/AGENTS.md` (sentinel marker found) from an unrelated empty cwd => global ~/.codex/AGENTS.md is the correct target. Also: existing global CLAUDE.md is 18 lines, fully assistant-agnostic.
- [ ] Decide the source-of-truth strategy (shared vs separate vs hybrid) — ask the user
- [ ] Add the chosen source file (new `AGENTS.md`, or reuse `home/programs/claude-code/CLAUDE.md`)
- [ ] Wire `home.file.".codex/AGENTS.md".source = ...;` into `home/programs/codex.nix` (merge with existing `home.file = skills.files;`)
- [x] Verified: built home config with codex + claude-code enabled; ~/.codex/AGENTS.md and ~/.claude/CLAUDE.md both generated and byte-identical (shared source); nix flake check exit 0
- [x] Updated root CLAUDE.md Boundaries note + home/lib/ai/CLAUDE.md to document the shared global-instructions.md

## Summary of Changes

Deployed a global Codex instructions file to `~/.codex/AGENTS.md`, refactored to share a single neutral source with claude-code's `~/.claude/CLAUDE.md`.

- Moved `home/programs/claude-code/CLAUDE.md` → `home/lib/ai/global-instructions.md` (verbatim, git rename) as the shared source of truth.
- `home/programs/claude-code/default.nix` — `.claude/CLAUDE.md` now sources `../../lib/ai/global-instructions.md`.
- `home/programs/codex.nix` — added `.codex/AGENTS.md".source = ../lib/ai/global-instructions.md`, merged with `skills.files`.
- Docs: root `CLAUDE.md` Boundaries note + `home/lib/ai/CLAUDE.md` Structure block updated; noted Cursor is not wired to the global file.

Research: confirmed empirically (`codex debug prompt-input` with a sentinel $CODEX_HOME/AGENTS.md) that Codex 0.135.0 injects the global ~/.codex/AGENTS.md. The existing global instructions are assistant-agnostic, so sharing is safe.

Validation: built a home-manager activation package with codex + claude-code enabled — ~/.codex/AGENTS.md and ~/.claude/CLAUDE.md generated and byte-identical. `nix flake check` exit 0. Subagent + user review passed.

Note: skill-library/home consumers remain unguarded by `nix flake check` (it builds packages only) — standing limitation, not introduced here.
