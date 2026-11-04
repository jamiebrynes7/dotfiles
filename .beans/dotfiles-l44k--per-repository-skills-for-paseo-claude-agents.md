---
# dotfiles-l44k
title: Per-repository skills for Paseo Claude agents
status: todo
type: epic
created_at: 2026-11-04T15:35:46Z
updated_at: 2026-11-04T15:35:46Z
---

**Goal:** Skills declared in Nix with the repositories they apply to load into Paseo Claude agents created in those repositories, and nowhere else.

**Spec:** docs/specs/2026-11-04-paseo-repo-skills.md

**Testing seam:** `nix flake check`: a fixture-rendering check for the generated plugins and config, `node:test` unit tests for the new plugin's server code, and the existing per-plugin typecheck and SDK-version checks. Plus the manual end-to-end check in the spec's Testing seams.
