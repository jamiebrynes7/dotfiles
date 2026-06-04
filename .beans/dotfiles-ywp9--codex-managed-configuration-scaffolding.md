---
# dotfiles-ywp9
title: Codex managed configuration scaffolding
status: todo
type: epic
created_at: 2026-06-04T10:10:22Z
updated_at: 2026-06-04T10:10:22Z
---

**Goal:** Manage selected Codex config declaratively from Nix via a profile-overlay file + wrapped binary, without clobbering the Codex-written `~/.codex/config.toml`.

**Architecture:** Nix renders a read-only `~/.codex/dotfiles.config.toml` overlay (via `pkgs.formats.toml`) and installs a `~/.local/bin/codex` wrapper that always execs `codex --profile dotfiles`. A single example knob (`dotfiles.programs.codex.hooks`, bool, default true) renders `[features].hooks`, proving the pipeline. Prereq refactor: a shared, de-duplicated `dotfiles.programs.zsh.extraSessionPaths` option replaces claude-code's raw PATH export.

**Tech Stack:** Nix flakes, home-manager, nix-darwin; `pkgs.formats.toml`, `pkgs.writeShellScript`, `home.sessionPath`, `home.activation`.

**Spec:** docs/specs/2026-06-04-codex-config.md
