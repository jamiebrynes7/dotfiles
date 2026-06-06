---
# dotfiles-b2sy
title: git pre-commit formatting hook (Nix + Rust)
status: todo
type: feature
priority: normal
created_at: 2026-05-24T14:36:19Z
updated_at: 2026-06-06T17:13:42Z
---

Replace the originally-planned Claude Code agent (`PostToolUse`) hook with a version-controlled **git pre-commit hook** that blocks commits containing unformatted Nix or Rust. Applies to any committer (human or agent, any editor); CI's `nix flake check` stays the authoritative gate.

**Architecture:** committed `.githooks/pre-commit` script selected via `core.hooksPath`, auto-wired by this repo's own devShell `shellHook` (zero-touch after `direnv allow`).

**Spec:** docs/specs/2026-06-06-git-precommit-formatting-hook.md

## Behavior

- On staged `*.nix` → `nixfmt --check` on all tracked `.nix` files.
- On staged `*.rs` → `cargo fmt --manifest-path crates/Cargo.toml --all --check`.
- Check-only (never mutates/re-stages). `set -e`: any violation OR a missing formatter exits non-zero and blocks the commit.

## Tasks (children)

- Write `.githooks/pre-commit` formatting gate
- Auto-wire `core.hooksPath` via devShell shellHook
- Document the hook in CLAUDE.md
