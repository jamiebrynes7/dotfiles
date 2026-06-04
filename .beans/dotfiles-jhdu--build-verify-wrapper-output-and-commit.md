---
# dotfiles-jhdu
title: Build, verify wrapper output, and commit
status: completed
type: task
priority: normal
created_at: 2026-06-04T13:51:47Z
updated_at: 2026-06-04T14:12:18Z
parent: dotfiles-16g2
blocked_by:
    - dotfiles-js9n
---

**Files:**
- No source edits; builds and commits the change from the previous task.

- [ ] **Step 1: Validate the flake**

Run: `nix flake check`
Expected: PASS (no eval/build errors).

- [ ] **Step 2: Inspect the generated wrapper script**

Build the home configuration's codex wrapper and confirm the injected flags. From the repo root, evaluate the wrapper store path and read it — easiest is to grep the built script after a dry build, or inspect via:

Run: `nix eval --raw .#<your-home-config>.config.home.activation.codexStableLink.data 2>/dev/null | grep -o 'codex-wrapper'` (optional sanity check)

The authoritative check happens post-switch (next task). At minimum confirm `nix flake check` passed and there are no references to `--profile` or `codexConfig` left:

Run: `grep -nE 'profile|codexConfig|dotfiles.config.toml' home/programs/codex/default.nix`
Expected: no matches.

- [ ] **Step 3: Commit**

```bash
git add home/programs/codex/default.nix docs/specs/2026-06-04-codex-config-c-injection.md docs/specs/2026-06-04-codex-config.md
git commit -m "$(cat <<'MSG'
home/programs/codex: inject managed config via -c instead of --profile

The --profile dotfiles overlay file was clobbered by Codex, which writes
runtime state (model/NUX/tier) to the active user layer. Switch to
wrapper-injected `-c key=value` session flags, which Codex never persists,
and drop the overlay file. config.toml stays fully Codex-owned.

Bean: dotfiles-ixms
MSG
)"
```

Also `git add` the bean files created/modified for this work alongside the commit.

## Summary of Changes

Folded into the `dotfiles-js9n` implementation commit (57f4bba). `nix flake check` passed there, no `--profile`/`codexConfig` references remain, and the code + bean were committed together. No separate work needed.
