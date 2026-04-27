---
# dotfiles-fo1w
title: Improve and standardize package update scripts
status: todo
type: feature
priority: normal
created_at: 2026-04-27T10:44:37Z
updated_at: 2026-04-27T11:04:55Z
---

Standardize the package update scripts under `packages/*/update.sh` and add two behavior improvements: skipping hash recomputation when the resolved version hasn't changed, and honoring a per-package pin file that opts the package out of auto-updates.

## Background

Three update scripts exist today:

- `packages/cship/update.sh` — release-tarball flow with a `PLATFORM_MAP`, fetches per-platform hashes, writes `hashes.json`.
- `packages/plannotator/update.sh` — near-duplicate of cship (different platform suffix scheme and binary name), same `hashes.json` shape.
- `packages/beans/update.sh` — `main`-branch unstable flow, computes source hash + Go vendor hash + pnpm deps hash, writes `data.json`.

cship and plannotator are nearly copy-pasted. All three always recompute every hash even when the upstream version hasn't moved, and there is no way to tell the periodic update job "leave this package alone for now".

## Goals

- Reduce duplication between `cship` and `plannotator` (and leave a clean shape for future release-tarball packages).
- Make repeated runs of an update script cheap when nothing changed upstream.
- Give a simple, in-tree mechanism to pin a package to a specific version and skip it during auto-updates.

## Children

- **dotfiles-4d6w** — Skip hash recomputation when upstream version is unchanged.
- **dotfiles-56hj** — Add pin-file marker to opt packages out of auto-updates (includes documenting the convention).

## Todo

- [ ] Audit the three existing scripts and decide on a shared structure (shared library vs. per-script convention) — keep it pragmatic, only factor out what is actually duplicated.
- [ ] Standardize the metadata file shape and naming (currently `hashes.json` for cship/plannotator, `data.json` for beans) where it makes sense; document any intentional differences.
- [ ] Standardize CLI surface: `update.sh [VERSION]` resolution, error messages, exit codes.
- [ ] Verify each script still works end-to-end after the refactor (run against current upstream, confirm the metadata file is byte-identical when there are no changes).
