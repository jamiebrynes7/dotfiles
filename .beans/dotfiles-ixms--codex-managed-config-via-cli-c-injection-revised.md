---
# dotfiles-ixms
title: Codex managed config via CLI -c injection (revised)
status: completed
type: epic
priority: normal
created_at: 2026-06-04T13:51:14Z
updated_at: 2026-06-04T14:57:32Z
---

**Goal:** Manage selected Codex settings declaratively from Nix by injecting `-c key=value` overrides from the `~/.local/bin/codex` wrapper, replacing the broken `--profile` overlay approach.

**Architecture:** Codex writes runtime state (model/NUX/tier) to whichever config file is the active user layer, so a read-only Nix symlink in any written layer gets clobbered. CLI `-c` flags are a session-only layer Codex never persists, so they carry managed settings without any file to clobber; `~/.codex/config.toml` stays fully Codex-owned. Tradeoff: `-c` is precedence 30 (enforced, above project config) rather than overridable defaults — accepted for the one current knob.

**Tech Stack:** Nix flakes, home-manager, pkgs.writeShellScript.

**Spec:** docs/specs/2026-06-04-codex-config-c-injection.md

Supersedes the broken `--profile` overlay approach from completed epic dotfiles-ywp9.

## Summary of Changes

Shipped the `-c` injection vehicle for Codex managed config in 57f4bba, replacing the broken `--profile` overlay. `features.hooks` flows end to end via wrapper-injected `-c 'features.hooks=<bool>'`; config.toml stays fully Codex-owned. Spec: docs/specs/2026-06-04-codex-config-c-injection.md.
