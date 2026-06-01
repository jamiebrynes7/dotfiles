---
# dotfiles-iex2
title: Codex ignores personal skills due to symlinked SKILL.md files
status: completed
type: bug
priority: high
created_at: 2026-06-01T16:21:57Z
updated_at: 2026-06-01T16:43:01Z
---

## Context

Codex only exposes bundled \`.system\` skills, ignoring user skills under \`~/.codex/skills/\`.

## Root Cause

Codex looks in \`~/.codex/skills\` but ignores the current Home Manager layout:

\`\`\`
~/.codex/skills/<skill>/              real directory
~/.codex/skills/<skill>/SKILL.md      symlink to /nix/store/...
\`\`\`

Codex follows symlinked skill *directories* but intentionally ignores symlinked \`SKILL.md\` *files* (see \`codex-rs/core-skills/src/loader.rs\` and the \`ignores_symlinked_skill_file_for_user_scope\` test). It only parses files named exactly \`SKILL.md\`.

The dotfiles \`home/lib/ai/skills/default.nix\` exposes each processed skill dir via \`home.file\` with \`recursive = true\`, which creates real target directories containing symlinked files. Codex needs the opposite: a symlinked skill directory.

## Recommended Fix

Add a \`recursive ? true\` parameter to \`mkSkillFiles\` in \`home/lib/ai/skills/default.nix\`, threading it into the \`home.file\` entry. Call it with \`recursive = false\` from \`home/programs/codex.nix\`. Default stays \`true\` so Claude Code and Cursor are unaffected.

## Todo

- [x] Add \`recursive ? true\` param to \`mkSkillFiles\` and thread into \`home.file\` source entry
- [x] Set \`recursive = false\` in the codex.nix \`mkSkillFiles\` call
- [x] Run \`nix flake check\`
- [x] Validate installed shape (symlinked skill dirs, codex prompt-input includes personal skills)

## Validation

\`\`\`sh
ls -la ~/.codex/skills/brainstorming
find ~/.codex/skills -mindepth 2 -maxdepth 2 -name SKILL.md -type l -print
codex debug prompt-input 'noop'
\`\`\`

Expected: \`~/.codex/skills/<skill>\` is a symlink; no symlinked \`SKILL.md\` files in real dirs; personal skills appear in \`<skills_instructions>\`.

## Summary of Changes

Added a `recursive ? true` parameter to `mkSkillFiles` in `home/lib/ai/skills/default.nix` and threaded it into the `home.file` source entry. The codex module (`home/programs/codex.nix`) now calls `mkSkillFiles` with `recursive = false`, so each `~/.codex/skills/<skill>` is a symlinked directory (with `SKILL.md` a real file inside the store path) rather than a real directory containing a symlinked `SKILL.md`. Codex follows symlinked skill directories but ignores symlinked `SKILL.md` files, so this makes it load personal skills.

Claude Code and Cursor are unaffected: they omit the parameter and keep the default `recursive = true`. Updated the `mkSkillFiles` contract docs in `home/lib/ai/CLAUDE.md` and added a load-bearing note near `processSkill`.

Verified by the user on a real switch: skill dirs are symlinks, no symlinked `SKILL.md` files remain, and personal skills appear in the codex `<skills_instructions>` block.
