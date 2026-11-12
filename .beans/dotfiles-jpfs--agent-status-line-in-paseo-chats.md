---
# dotfiles-jpfs
title: Agent status line in Paseo chats
status: completed
type: epic
priority: normal
created_at: 2026-11-12T11:42:57Z
updated_at: 2026-11-12T14:43:08Z
---

**Goal:** Each Paseo agent keeps a one-line, agent-written status (what it's doing, what it's waiting on) at the bottom of its chat, and Claude agents are made to refresh it before every turn ends.

**Spec:** docs/specs/2026-11-12-paseo-agent-status.md

**Testing seam:** the plugin's `node --test` suite and typecheck through the existing `ts/` overlay checks (`nix flake check`), plus a manual check in Paseo following the paseo-plugin skill's checklist.
