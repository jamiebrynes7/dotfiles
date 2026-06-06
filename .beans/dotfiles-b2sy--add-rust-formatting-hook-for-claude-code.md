---
# dotfiles-b2sy
title: git pre-commit formatting hook (Nix + Rust)
status: completed
type: feature
priority: normal
created_at: 2026-05-24T14:36:19Z
updated_at: 2026-06-06T17:38:00Z
order: k
---

Replace the originally-planned Claude Code agent (`PostToolUse`) hook with a version-controlled **git pre-commit hook** that blocks commits containing unformatted Nix or Rust. Applies to any committer (human or agent, any editor); CI's `nix flake check` stays the authoritative gate.

**Architecture:** committed `.githooks/pre-commit` script selected via `core.hooksPath`, auto-wired by this repo's own devShell `shellHook` (zero-touch after `direnv allow`).

**Spec:** docs/specs/2026-06-06-git-precommit-formatting-hook.md

## Behavior

- On staged `*.nix` → `nixfmt --check` on all tracked `.nix` files.
- On staged `*.rs` → `cargo fmt --all --check`.
- Check-only (never mutates/re-stages). `set -e`: any violation OR a missing formatter exits non-zero and blocks the commit.

## Tasks (children)

- Write `.githooks/pre-commit` formatting gate
- Auto-wire `core.hooksPath` via devShell shellHook
- Document the hook in CLAUDE.md

## Summary of Changes

Shipped the version-controlled git pre-commit formatting hook, replacing the originally-planned Claude Code agent hook. Delivered across three tasks:

- **dotfiles-o7so** — `.githooks/pre-commit`: check-only gate running `nixfmt --check` (all tracked `.nix`, NUL-safe) and `cargo fmt --all --check` (workspace) when matching files are staged; `set -e` + EXIT trap block on any violation or missing formatter.
- **dotfiles-3pth** — devShell `shellHook` auto-wires `core.hooksPath=.githooks` (repo-specific `extraEnv`, no downstream leak), so the hook activates with no manual setup.
- **dotfiles-dr6g** — documented in `CLAUDE.md` (Commands + Formatting), freshness bumped.

Also did prep work **dotfiles-36rg** (formatted the Rust workspace, which had pre-existing rustfmt drift) so the hook lands clean. Verified end-to-end: a real mis-formatted commit is blocked; the hook ran on its own feature commits. CI's `nix flake check` remains the authoritative gate.
