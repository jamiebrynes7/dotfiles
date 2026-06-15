---
# dotfiles-16g2
title: Swap profile overlay for -c injection in codex module
status: completed
type: feature
priority: normal
created_at: 2026-06-04T13:51:20Z
updated_at: 2026-06-04T14:57:32Z
parent: dotfiles-ixms
---

Rework home/programs/codex/default.nix so managed settings flow to Codex via wrapper-injected `-c key=value` flags instead of a `--profile dotfiles` overlay file. Owns the entire change: the `managedConfig`/`configArgs` renderer, the rewritten `codexWrapper`, and removal of the `.codex/dotfiles.config.toml` deployment. The `extraSessionPaths` zsh refactor and `~/.local/bin` wiring already landed in earlier commits and are unchanged. AGENTS.md, skills/, and hooks.json deployments are untouched.

## Summary of Changes

All child tasks completed: the codex module now injects managed settings via wrapper `-c` flags (dotfiles-js9n), the change was built/committed (dotfiles-jhdu, folded into 57f4bba), and post-switch behavior was validated (dotfiles-hrnr).
