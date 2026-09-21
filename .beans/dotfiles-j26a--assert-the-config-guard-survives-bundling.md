---
# dotfiles-j26a
title: Assert the config guard survives bundling
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:26:11Z
updated_at: 2026-09-21T17:30:07Z
parent: dotfiles-a3i5
blocked_by:
    - dotfiles-9th1
---

**Files:**
- Modify: `packages/paseo/default.nix:66` — append to the existing `postInstall`

`--replace-fail` proves the *source* changed. The daemon's runtime closure is computed with `@vercel/nft`, so a patched file that never makes it into the traced output would ship an unguarded daemon silently — the same failure class the existing node-pty assertion guards against.

- [ ] **Step 1: Append the assertion to `postInstall`**

At the end of the existing `postInstall` string, after the node-pty copy:

```nix
    # --replace-fail proves the source changed; this proves the guard reached $out.
    if ! grep -rq ${lib.escapeShellArg configGuardMessage} "$out/lib/paseo"; then
      echo "paseo: config-write guard missing from the built daemon" >&2
      echo "paseo: the postPatch applied but the file never reached the bundle." >&2
      exit 1
    fi
```

`lib` is already an argument of this file, and `configGuardMessage` comes from the previous task's `let` binding.

- [ ] **Step 2: Format**

Run: `nixfmt packages/paseo/default.nix`

- [ ] **Step 3: Rebuild and confirm it passes**

Run: `nix build .#paseo -o /tmp/paseo-guard`

Expected: success (the guard is present, so the assertion is a no-op).

- [ ] **Step 4: Prove the assertion can fail**

Temporarily change the grep pattern to a string that is not in the bundle:

```nix
    if ! grep -rq "this string is not in the bundle" "$out/lib/paseo"; then
```

Run: `nix build .#paseo -o /tmp/paseo-guard 2>&1 | tail -5`

Expected: the build fails with `paseo: config-write guard missing from the built daemon`. Then revert the pattern back to `${lib.escapeShellArg configGuardMessage}` and rebuild to confirm success again.

- [ ] **Step 5: Commit**

```bash
git add packages/paseo/default.nix
git commit -m "packages/paseo: assert the config guard reaches the built daemon" -m "Bean: dotfiles-j26a"
```
