---
# dotfiles-zo7y
title: Package agent skills as Claude Code plugins
status: todo
type: epic
created_at: 2026-08-02T12:10:20Z
updated_at: 2026-08-02T12:10:20Z
---

**Goal:** Bundle skills and hooks into named Claude Code skills-directory plugins (`df-base`, `df-plannotator`, `df-beans`) so they can be enabled and disabled per project.

**Architecture:** A new `dotfiles.ai.plugins.<name>` option namespace (declared in `home/lib/ai/plugins/module.nix`) is the single place features declare skills + hooks. A renderer in `home/lib/ai/plugins/default.nix` builds one derivation per plugin laid out as `.claude-plugin/plugin.json` + `skills/` + `hooks/hooks.json`, installed to `~/.claude/skills/df-<name>/`. Claude Code discovers these in place as `df-<name>@skills-dir` — no marketplace, no install step, no cache invalidation. Codex and Cursor keep today's loose skill fan-out by flattening the same declarations through the existing `mkSkillFiles`.

**Tech Stack:** Nix flakes, home-manager modules, `pkgs.runCommand`, the existing `process-frontmatter` Python tool, Claude Code 2.1.220 plugin CLI.

**Spec:** docs/specs/2026-08-02-agent-plugins.md

All three design assumptions were verified empirically before planning (symlinked-file plugin trees are discovered; `defaultEnabled: false` holds and `enabledPlugins` overrides it; `claude plugin validate` runs offline). See the spec's Validation section.
