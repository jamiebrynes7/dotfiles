---
# dotfiles-iex2
title: Codex ignores personal skills due to symlinked SKILL.md files
status: in-progress
type: bug
priority: high
created_at: 2026-06-01T16:21:57Z
updated_at: 2026-06-01T16:23:10Z
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
- [ ] Validate installed shape (symlinked skill dirs, codex prompt-input includes personal skills)

## Validation

\`\`\`sh
ls -la ~/.codex/skills/brainstorming
find ~/.codex/skills -mindepth 2 -maxdepth 2 -name SKILL.md -type l -print
codex debug prompt-input 'noop'
\`\`\`

Expected: \`~/.codex/skills/<skill>\` is a symlink; no symlinked \`SKILL.md\` files in real dirs; personal skills appear in \`<skills_instructions>\`.
