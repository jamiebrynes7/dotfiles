---
# dotfiles-3pth
title: Auto-wire core.hooksPath via devShell shellHook
status: completed
type: task
priority: normal
created_at: 2026-06-06T17:14:20Z
updated_at: 2026-06-06T17:35:11Z
order: V
parent: dotfiles-b2sy
---

**Files:**
- Modify: `flake.nix` (the repo's own `devShells = mkShells { ... }` block near the bottom — currently around lines 246-251, the `extraEnv` attr)

Add a `shellHook` to **this repo's own devShell only** so entering it sets `core.hooksPath=.githooks`. MUST go in the repo-specific `extraEnv` passed to `mkShells`, NOT in the shared `mkShells`/`baseShellPkgs` helper — `mkShells` is exported as `lib.mkShells` and reused by downstream system repos; putting the hook there would leak the `git config` into every downstream devShell.

`mkOne` merges `extraEnv pkgs` into `pkgs.mkShell` via `//`, so a `shellHook` key passes straight through.

- [x] **Step 1: Add the shellHook to the repo devShell**

Change the `devShells` block so `extraEnv` returns a `shellHook` alongside `RUST_SRC_PATH`:

```nix
devShells = mkShells {
  extraPackages = pkgs: [ pkgs.dotfiles.internal.rustToolchain ];
  extraEnv = pkgs: {
    RUST_SRC_PATH = "${pkgs.dotfiles.internal.rustToolchain}/lib/rustlib/src/rust/library";
    shellHook = ''
      git config core.hooksPath .githooks
    '';
  };
};
```

`git config core.hooksPath` is repo-local (writes `.git/config`) and idempotent — safe to run on every shell entry. (A `git rev-parse` guard was considered for the out-of-repo case but dropped: this devShell is only ever entered in-repo via direnv.)

- [x] **Step 2: Format the flake**

Run: `nixfmt flake.nix`
Expected: no diff beyond the edit (file already nixfmt-clean).

- [x] **Step 3: Re-enter the devShell and verify the wiring**

Run: `direnv reload` (or exit and re-enter the shell), then `git config core.hooksPath`
Expected: prints `.githooks`.

- [x] **Step 4: End-to-end check (requires the hook script from the sibling task)**

If `.githooks/pre-commit` exists: stage a deliberately mis-formatted `.nix` file and attempt a real commit.
Run: `git add <misformatted>.nix && git commit -m "test"; echo "exit=$?"`
Expected: commit is blocked, `exit=1`, fix hint shown. Then `git checkout` the file to restore.

- [x] **Step 5: Commit**

```bash
git add flake.nix
git commit -m "flake: auto-wire core.hooksPath in devShell

Bean: dotfiles-b2sy"
```

## Summary of Changes

Added a `shellHook` to the repo's own `devShells` block in `flake.nix` (in the repo-specific `extraEnv`, not the shared `lib.mkShells` helper, so it can't leak into downstream system repos). On entering the devShell it runs `git config core.hooksPath .githooks`, activating the committed pre-commit hook with zero manual setup.

Per user review, the originally-planned `git rev-parse` guard was dropped — the devShell is only ever entered in-repo via direnv, so the guard could never fire. Verified via `nix develop --command` that `core.hooksPath` becomes `.githooks`, and end-to-end that a real `git commit` of a mis-formatted `.nix` file is blocked. Subagent and user reviews both passed.
