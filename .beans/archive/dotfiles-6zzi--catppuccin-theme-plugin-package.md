---
# dotfiles-6zzi
title: catppuccin-theme plugin package
status: completed
type: feature
priority: normal
created_at: 2026-09-21T17:24:09Z
updated_at: 2026-10-05T13:36:22Z
parent: dotfiles-5nj7
---

Package the first external plugin. Owns `packages/paseo-plugin-catppuccin-theme/default.nix`: a `fetchFromGitHub` pinned by commit SHA plus a `runCommand` that copies the plugin subdirectory out of the monorepo.

## Summary of Changes

The plugin is packaged at upstream commit c9063de (m8y6) and enabled by default in the paseo module, with a per-host opt-out (iv3m).
