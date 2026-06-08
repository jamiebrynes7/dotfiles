---
# dotfiles-o7so
title: Write .githooks/pre-commit formatting gate
status: completed
type: task
priority: normal
created_at: 2026-06-06T17:14:08Z
updated_at: 2026-06-06T17:28:25Z
parent: dotfiles-b2sy
---

**Files:**
- Create: `.githooks/pre-commit` (POSIX sh, must be `chmod +x`)

The script blocks a commit when staged Nix/Rust files imply the repo isn't fully formatted. Uses `set -e` so a formatter reporting violations *or* a missing formatter (command-not-found, exit 127) aborts the hook. Check-only — never edits or re-stages files.

- [x] **Step 1: Create the hook script**

Write `.githooks/pre-commit` with exactly this content:

```sh
#!/bin/sh
# Pre-commit formatting gate (Nix + Rust).
# Selected via `core.hooksPath=.githooks` (auto-wired by the devShell shellHook).
# Check-only: reports + blocks, never mutates the tree.
set -e

print_fix_hint() {
  status=$?
  [ "$status" -eq 0 ] && return 0
  {
    echo
    echo "pre-commit: formatting check failed (or a formatter was missing from PATH)."
    echo "Commit from inside the devShell, then fix with:"
    echo "  nixfmt \$(git ls-files '*.nix')"
    echo "  cargo fmt --all"
  } >&2
}
trap print_fix_hint EXIT

staged=$(git diff --cached --name-only --diff-filter=ACM)

if printf '%s
' "$staged" | grep -q '\.nix$'; then
  echo "pre-commit: nixfmt --check (all tracked .nix)"
  git ls-files -z '*.nix' | xargs -0 nixfmt --check
fi

if printf '%s
' "$staged" | grep -q '\.rs$'; then
  echo "pre-commit: cargo fmt --check (workspace)"
  cargo fmt --all --check
fi
```

Notes: the formatters are run as bare commands (not wrapped in `if`/`||`) so `set -e` catches both violations and command-not-found. The `trap` prints the recovery hint only on a non-zero exit.

- [x] **Step 2: Make it executable**

Run: `chmod +x .githooks/pre-commit`
Then: `git add .githooks/pre-commit && git update-index --chmod=+x .githooks/pre-commit`
Verify: `git ls-files -s .githooks/pre-commit` shows mode `100755`.

- [x] **Step 3: Verify it blocks an unformatted Nix change**

From inside the devShell, temporarily add a badly-formatted line to a tracked `.nix` file (e.g. `flake.nix`), stage it, and run the hook directly (no wiring needed yet):

Run: `git add flake.nix && ./.githooks/pre-commit; echo "exit=$?"`
Expected: prints `nixfmt --check ...`, lists the offending file, then `exit=1` and the fix hint.

- [x] **Step 4: Verify it passes when formatted**

Run: `nixfmt flake.nix && git add flake.nix && ./.githooks/pre-commit; echo "exit=$?"`
Expected: `exit=0`, no fix hint. Restore `flake.nix` with `git checkout flake.nix` afterwards.

- [x] **Step 5: Verify the no-op path**

Unstage everything and run the hook with nothing staged:
Run: `git reset && ./.githooks/pre-commit; echo "exit=$?"`
Expected: no formatter output, `exit=0`.

- [x] **Step 6: Commit**

```bash
git add .githooks/pre-commit
git commit -m "githooks: add pre-commit formatting hook script

Bean: dotfiles-b2sy"
```

## Summary of Changes

Added `.githooks/pre-commit` (POSIX sh, mode 100755): a check-only formatting gate. When staged files include `*.nix` it runs `nixfmt --check` over all tracked `.nix` (NUL-safe via `git ls-files -z | xargs -0`); when they include `*.rs` it runs `cargo fmt --all --check` over the workspace. `set -e` plus an `EXIT` trap mean any violation or a missing formatter blocks the commit and prints a fix hint; the hook never mutates the tree.

During implementation: corrected a stale `crates/Cargo.toml` manifest path to plain `cargo fmt --all` (the workspace manifest is at the repo root) across this bean, the parent b2sy, and the spec. Verified block/pass/no-op for both Nix and Rust paths. A subagent review and a user review both passed; applied the reviewer's word-splitting hardening (xargs -0).
