---
# dotfiles-a3i5
title: paseo daemon config-write guard
status: todo
type: feature
created_at: 2026-09-21T17:24:09Z
updated_at: 2026-09-21T17:24:09Z
parent: dotfiles-5nj7
---

Patch the vendored daemon so it refuses to overwrite a Nix-managed `config.json`. Owns `packages/paseo/default.nix`: a `postPatch` adding a symlink guard to `savePersistedConfig`, and a `postInstall` assertion proving the guard survived bundling.
