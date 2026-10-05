---
# dotfiles-6zzi
title: catppuccin-theme plugin package
status: in-progress
type: feature
priority: normal
created_at: 2026-09-21T17:24:09Z
updated_at: 2026-10-05T13:34:33Z
parent: dotfiles-5nj7
---

Package the first external plugin. Owns `packages/paseo-plugin-catppuccin-theme/default.nix`: a `fetchFromGitHub` pinned by commit SHA plus a `runCommand` that copies the plugin subdirectory out of the monorepo.
