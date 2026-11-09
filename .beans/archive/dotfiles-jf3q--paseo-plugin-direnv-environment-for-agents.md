---
# dotfiles-jf3q
title: 'paseo plugin: direnv environment for agents'
status: completed
type: epic
priority: normal
created_at: 2026-10-18T16:07:33Z
updated_at: 2026-11-06T23:08:56Z
---

**Goal:** Launch every paseo agent with the environment direnv gives its directory, with direnv's own allow list as the only trust authority.

**Spec:** docs/specs/2026-10-18-paseo-direnv-plugin.md

**Testing seam:** the per-plugin typecheck and sdk-version flake checks plus `paseo-plugin-requirements`, and the manual host matrix in the spec's "Testing seams" section.

**Already done:** the `ts/` plugin scaffolding (`buildPaseoPlugin`, per-plugin flake checks, the packages convention and `mkDefault` registration), which landed with the last-response plugin (dotfiles-8v5j).

## Summary of Changes

All three children landed: the launch hook that gives agents their directory's direnv environment (dotfiles-e2gj), auto-allowing new worktrees of allowed projects (dotfiles-23hw), and the workspace header Allow / Warm button (dotfiles-lfp9).

Closed at the user's request. The spec's manual host matrix was not re-run in full when closing; dotfiles-lfp9 records the in-app checks that were.
