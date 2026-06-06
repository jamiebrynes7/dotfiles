---
# dotfiles-3pth
title: Auto-wire core.hooksPath via devShell shellHook
status: todo
type: task
created_at: 2026-06-06T17:14:20Z
updated_at: 2026-06-06T17:14:20Z
parent: dotfiles-b2sy
---

**Files:**
- Modify: `flake.nix` (the repo's own `devShells = mkShells { ... }` block near the bottom — currently around lines 246-251, the `extraEnv` attr)

Add a `shellHook` to **this repo's own devShell only** so entering it sets `core.hooksPath=.githooks`. MUST go in the repo-specific `extraEnv` passed to `mkShells`, NOT in the shared `mkShells`/`baseShellPkgs` helper — `mkShells` is exported as `lib.mkShells` and reused by downstream system repos; putting the hook there would leak the `git config` into every downstream devShell.

`mkOne` merges `extraEnv pkgs` into `pkgs.mkShell` via `//`, so a `shellHook` key passes straight through.

- [ ] **Step 1: Add the shellHook to the repo devShell**

Change the `devShells` block so `extraEnv` returns a `shellHook` alongside `RUST_SRC_PATH`:

```nix
devShells = mkShells {
  extraPackages = pkgs: [ pkgs.dotfiles.internal.rustToolchain ];
  extraEnv = pkgs: {
    RUST_SRC_PATH = "${pkgs.dotfiles.internal.rustToolchain}/lib/rustlib/src/rust/library";
    shellHook = ''
      if git rev-parse --git-dir >/dev/null 2>&1; then
        git config core.hooksPath .githooks
      fi
    '';
  };
};
```

The `git rev-parse` guard avoids errors if the shell is ever entered outside a git repo. `git config` here is repo-local and idempotent.

- [ ] **Step 2: Format the flake**

Run: `nixfmt flake.nix`
Expected: no diff beyond the edit (file already nixfmt-clean).

- [ ] **Step 3: Re-enter the devShell and verify the wiring**

Run: `direnv reload` (or exit and re-enter the shell), then `git config core.hooksPath`
Expected: prints `.githooks`.

- [ ] **Step 4: End-to-end check (requires the hook script from the sibling task)**

If `.githooks/pre-commit` exists: stage a deliberately mis-formatted `.nix` file and attempt a real commit.
Run: `git add <misformatted>.nix && git commit -m "test"; echo "exit=$?"`
Expected: commit is blocked, `exit=1`, fix hint shown. Then `git checkout` the file to restore.

- [ ] **Step 5: Commit**

```bash
git add flake.nix
git commit -m "flake: auto-wire core.hooksPath in devShell

Bean: dotfiles-b2sy"
```
