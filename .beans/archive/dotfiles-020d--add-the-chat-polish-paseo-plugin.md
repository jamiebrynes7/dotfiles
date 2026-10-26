---
# dotfiles-020d
title: Add the chat-polish paseo plugin
status: completed
type: task
priority: normal
created_at: 2026-10-22T10:43:37Z
updated_at: 2026-10-22T11:15:31Z
---

Package lthieu96/paseo-chat-polish (registry: lthieu96/chat-polish) as packages/paseo-plugin-paseo-chat-polish and enable it by default in home/programs/paseo.nix.

- [x] Package the plugin with its production npm deps
- [x] Wire it into the paseo module
- [x] nix flake check passes

## Summary of Changes

- packages/paseo-plugin-paseo-chat-polish: buildNpmPackage over the v0.7.0 tag commit, installing production deps (--omit=dev --ignore-scripts) since the daemon never runs a manifest build step for directory sources. autoPatchelf on Linux for sharp's prebuilt binaries.
- home/programs/paseo.nix: enabled by default (mkDefault), like the other plugins.
- Verified on aarch64-darwin: nix flake check passes, sharp loads from the built output. x86_64-linux evaluates but has not been built yet; CI's flake check will build it.
