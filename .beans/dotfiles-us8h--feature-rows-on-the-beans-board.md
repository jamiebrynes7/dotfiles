---
# dotfiles-us8h
title: Feature rows on the beans board
status: completed
type: epic
priority: normal
created_at: 2026-11-12T09:50:57Z
updated_at: 2026-11-12T11:06:14Z
---

**Goal:** Make it obvious which tasks belong to which feature on the beans paseo board by splitting epic lanes into per-feature rows.

**Spec:** docs/specs/2026-11-12-paseo-beans-feature-rows.md

**Testing seam:** the plugin's layout unit tests (the `paseo-plugin-beans-test` flake check), plus a hand check with `ts/paseo-demo.sh beans`.

## Summary of Changes

Epic lanes on the beans board now split into one row per feature. Each row has a header showing the title, id, status and done/total, and collapses to that header. The feature's card leads its status column. Searched or archived features head their rows as dimmed context cards. A toolbar button collapses or expands every feature row at once. Work landed in dotfiles-ty72 (PR #459) and dotfiles-zool.
