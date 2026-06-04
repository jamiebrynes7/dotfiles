---
# dotfiles-hrnr
title: Post-switch validation of -c injection
status: todo
type: task
priority: normal
created_at: 2026-06-04T13:51:56Z
updated_at: 2026-06-04T13:52:01Z
parent: dotfiles-16g2
blocked_by:
    - dotfiles-jhdu
---

**Files:**
- No edits; manual verification after `home-manager switch` (or the host's rebuild command).

Run these after applying the new configuration. No commit.

- [ ] **Step 1: Wrapper resolves and carries the -c flag, no --profile**

```bash
which codex                 # → ~/.local/bin/codex
cat "$(which codex)"        # body contains: exec /nix/store/.../bin/codex -c 'features.hooks=true' "$@"
grep -c -- --profile "$(which codex)"   # → 0
```
Expected: wrapper path is `~/.local/bin/codex`; body has `-c 'features.hooks=true'` and no `--profile`.

- [ ] **Step 2: Overlay file is gone**

```bash
ls -l ~/.codex/dotfiles.config.toml
```
Expected: "No such file or directory".

- [ ] **Step 3: config.toml is untouched and user-writable**

```bash
ls -l ~/.codex/config.toml   # not a symlink, mode rw for user
```
Expected: a regular writable file (not a /nix/store symlink). Optionally confirm Codex can still persist by running `codex` and trusting a directory or selecting a model — it should write to `~/.codex/config.toml` without error.

- [ ] **Step 4: The knob flows end to end**

Set `dotfiles.programs.codex.enableHooks = false` in the profile, rebuild, then:

```bash
grep -- "-c 'features.hooks=false'" "$(which codex)"
```
Expected: a match (the wrapper now injects `features.hooks=false`). Revert the change and rebuild afterward.
