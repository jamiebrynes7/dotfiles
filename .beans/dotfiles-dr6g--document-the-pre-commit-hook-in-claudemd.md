---
# dotfiles-dr6g
title: Document the pre-commit hook in CLAUDE.md
status: completed
type: task
priority: normal
created_at: 2026-06-06T17:14:27Z
updated_at: 2026-06-06T17:37:37Z
parent: dotfiles-b2sy
---

**Files:**
- Modify: `CLAUDE.md` (the `## Commands` section and/or `## Conventions`)

Add a short note so future contributors/agents know the hook exists and that commits should be made from inside the devShell (so `nixfmt`/`cargo` are on `PATH`).

- [x] **Step 1: Add a Commands bullet**

Under `## Commands`, add a bullet near the other format/check commands:

```markdown
- The repo has a `.githooks/pre-commit` formatting gate (Nix + Rust). It's auto-wired via `core.hooksPath` by the devShell `shellHook`, so commit from inside the devShell (`direnv` shell) where `nixfmt`/`cargo` are on `PATH`.
```

- [x] **Step 2: Add a Conventions note under Formatting**

In `## Conventions` → `### Formatting`, append:

```markdown
A `.githooks/pre-commit` hook blocks commits that leave `*.nix` or `*.rs` files unformatted (`nixfmt --check` / `cargo fmt --check`). CI's `nix flake check` remains the authoritative gate.
```

- [x] **Step 3: Update the freshness date**

Change the `Freshness:` line near the top of `CLAUDE.md` to today's date (`2026-06-06`).

- [x] **Step 4: Verify**

Run: `grep -n "githooks" CLAUDE.md`
Expected: matches in both the Commands and Conventions sections.

- [x] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "CLAUDE.md: document the pre-commit formatting hook

Bean: dotfiles-b2sy"
```

## Summary of Changes

Documented the pre-commit hook in `CLAUDE.md`: a `## Commands` note (hook exists, auto-wired via the devShell shellHook, commit from inside the devShell so the formatters are on PATH), a sentence extending `### Formatting` (hook blocks unformatted `*.nix`/`*.rs`; `nix flake check` is the authoritative gate), and bumped the freshness date to 2026-06-06. Per subagent review, the Formatting parenthetical was made exact (`cargo fmt --all --check`). Subagent and user reviews both passed.
