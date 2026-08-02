---
# dotfiles-nx0d
title: Move hook types into the plugin library
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:14:11Z
updated_at: 2026-08-02T12:14:11Z
parent: dotfiles-jali
blocked_by:
    - dotfiles-d6t2
---

The plugin renderer needs `hookType` and `mergeHooks` to build each plugin's `hooks/hooks.json`, but they currently live inside a program module (`home/programs/claude-code/hooks/types.nix`). A library must not import from a program module, so move the file into `home/lib/ai/plugins/` and repoint the two existing importers.

Pure move — no schema changes, no behaviour change. The `home-eval` check from the previous task is what proves nothing broke.

**Files:**
- Create: `home/lib/ai/plugins/hook-types.nix` (verbatim copy of the file below)
- Delete: `home/programs/claude-code/hooks/types.nix`
- Modify: `home/programs/claude-code/default.nix:23`
- Modify: `home/programs/claude-code/hooks/debug.nix:10`

- [ ] **Step 1: Move the file**

```bash
mkdir -p home/lib/ai/plugins
git mv home/programs/claude-code/hooks/types.nix home/lib/ai/plugins/hook-types.nix
```

Its contents are unchanged: a `{ lib }` function returning `{ hookEvents, hookCommandType, hookType, mergeHooks }`. Do not edit it in this task.

- [ ] **Step 2: Repoint the claude-code module**

In `home/programs/claude-code/default.nix`, line 23:

```nix
  hookTypes = import ../../lib/ai/plugins/hook-types.nix { inherit lib; };
```

- [ ] **Step 3: Repoint the debug hook module**

In `home/programs/claude-code/hooks/debug.nix`, line 10:

```nix
  hookTypes = import ../../../lib/ai/plugins/hook-types.nix { inherit lib; };
```

The path has one more `../` than the previous step: this file sits in `home/programs/claude-code/hooks/`.

- [ ] **Step 4: Verify eval still succeeds**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: passes, printing a store path. A wrong relative path fails here with `error: path '...' does not exist`.

- [ ] **Step 5: Confirm no stale references remain**

Run: `grep -rn "hooks/types.nix" home/`

Expected: no output.

- [ ] **Step 6: Format and commit**

```bash
nixfmt home/lib/ai/plugins/hook-types.nix home/programs/claude-code/default.nix home/programs/claude-code/hooks/debug.nix
git add -A home/
git commit -m "home/lib/ai: move hook types into the plugin library

The plugin renderer needs hookType/mergeHooks to build hooks.json, and a
library must not import from a program module.

Bean: dotfiles-nx0d"
```
