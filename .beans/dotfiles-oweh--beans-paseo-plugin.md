---
# dotfiles-oweh
title: beans paseo plugin
status: todo
type: epic
created_at: 2026-11-05T14:15:33Z
updated_at: 2026-11-05T14:15:33Z
---

**Goal:** A repo-local paseo plugin that shows a workspace's beans as a Kanban board, shows bean detail in the Explorer, and starts an agent on a ready bean.

**Spec:** docs/specs/2026-11-05-paseo-beans-plugin.md

**Testing seam:** the existing `ts/` flake checks (`<dir>-typecheck`, `<dir>-sdk-version`) and `paseo-plugin-requirements`, plus a manual pass on one host with the plugin enabled (spec §Testing seams).
