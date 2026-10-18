---
# dotfiles-jf3q
title: 'paseo plugin: direnv environment for agents'
status: todo
type: epic
created_at: 2026-10-18T16:07:33Z
updated_at: 2026-10-18T16:07:33Z
---

**Goal:** Launch every paseo agent with the environment direnv gives its directory, with direnv's own allow list as the only trust authority.

**Spec:** docs/specs/2026-10-18-paseo-direnv-plugin.md

**Testing seam:** the per-plugin typecheck and sdk-version flake checks plus `paseo-plugin-requirements`, and the manual host matrix in the spec's "Testing seams" section.

**Already done:** the `ts/` plugin scaffolding (`buildPaseoPlugin`, per-plugin flake checks, the packages convention and `mkDefault` registration), which landed with the last-response plugin (dotfiles-8v5j).
