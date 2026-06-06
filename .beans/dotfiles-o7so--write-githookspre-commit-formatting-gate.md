---
# dotfiles-o7so
title: Write .githooks/pre-commit formatting gate
status: todo
type: task
priority: normal
created_at: 2026-06-06T17:14:08Z
updated_at: 2026-06-06T17:14:43Z
parent: dotfiles-b2sy
---

**Files:**
- Create: `.githooks/pre-commit` (POSIX sh, must be `chmod +x`)

The script blocks a commit when staged Nix/Rust files imply the repo isn't fully formatted. Uses `set -e` so a formatter reporting violations *or* a missing formatter (command-not-found, exit 127) aborts the hook. Check-only — never edits or re-stages files.

- [ ] **Step 1: Create the hook script**

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
    echo "  cargo fmt --manifest-path crates/Cargo.toml --all"
  } >&2
}
trap print_fix_hint EXIT

staged=$(git diff --cached --name-only --diff-filter=ACM)

if printf '%s
' "$staged" | grep -q '\.nix$'; then
  echo "pre-commit: nixfmt --check (all tracked .nix)"
  nixfmt --check $(git ls-files '*.nix')
fi

if printf '%s
' "$staged" | grep -q '\.rs$'; then
  echo "pre-commit: cargo fmt --check (workspace)"
  cargo fmt --manifest-path crates/Cargo.toml --all --check
fi
```

Notes: the formatters are run as bare commands (not wrapped in `if`/`||`) so `set -e` catches both violations and command-not-found. The `trap` prints the recovery hint only on a non-zero exit.

- [ ] **Step 2: Make it executable**

Run: `chmod +x .githooks/pre-commit`
Then: `git add .githooks/pre-commit && git update-index --chmod=+x .githooks/pre-commit`
Verify: `git ls-files -s .githooks/pre-commit` shows mode `100755`.

- [ ] **Step 3: Verify it blocks an unformatted Nix change**

From inside the devShell, temporarily add a badly-formatted line to a tracked `.nix` file (e.g. `flake.nix`), stage it, and run the hook directly (no wiring needed yet):

Run: `git add flake.nix && ./.githooks/pre-commit; echo "exit=$?"`
Expected: prints `nixfmt --check ...`, lists the offending file, then `exit=1` and the fix hint.

- [ ] **Step 4: Verify it passes when formatted**

Run: `nixfmt flake.nix && git add flake.nix && ./.githooks/pre-commit; echo "exit=$?"`
Expected: `exit=0`, no fix hint. Restore `flake.nix` with `git checkout flake.nix` afterwards.

- [ ] **Step 5: Verify the no-op path**

Unstage everything and run the hook with nothing staged:
Run: `git reset && ./.githooks/pre-commit; echo "exit=$?"`
Expected: no formatter output, `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add .githooks/pre-commit
git commit -m "githooks: add pre-commit formatting hook script

Bean: dotfiles-b2sy"
```
