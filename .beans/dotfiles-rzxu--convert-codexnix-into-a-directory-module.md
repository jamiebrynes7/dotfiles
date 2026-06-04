---
# dotfiles-rzxu
title: Convert codex.nix into a directory module
status: todo
type: task
created_at: 2026-06-04T12:57:05Z
updated_at: 2026-06-04T12:57:05Z
parent: dotfiles-5gsf
---

Pure refactor, no behavior change. Convert the single-file codex module into a directory so it can host a hooks/ subdir, fixing the now-deeper relative paths. `home/default.nix` auto-imports both `*.nix` files and directories under `home/programs/`, importing a directory via its `default.nix` — so `codex.nix` and a `codex/` directory must NOT coexist (use `git mv`).

**Files:**
- Move: `home/programs/codex.nix` -> `home/programs/codex/default.nix`
- Modify: `home/programs/codex/default.nix` (relative-path fixups)

- [ ] **Step 1: Move the file**

```bash
mkdir -p home/programs/codex
git mv home/programs/codex.nix home/programs/codex/default.nix
```

- [ ] **Step 2: Fix the two relative paths (one dir deeper now)**

In `home/programs/codex/default.nix`, change the skills import:

```nix
  aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };
```

(was `../lib/ai/skills`), and the AGENTS.md source:

```nix
      ".codex/AGENTS.md".source = ../../lib/ai/global-instructions.md;
```

(was `../lib/ai/global-instructions.md`). No other paths change.

- [ ] **Step 3: Format**

Run: `nixfmt home/programs/codex/default.nix`

- [ ] **Step 4: Validate the flake still evaluates and builds**

Run: `nix flake check`
Expected: PASS (no behavior change; codex module evaluates from its new location).

- [ ] **Step 5: Commit**

```bash
git add -A home/programs/codex
git commit -m "home/programs/codex: convert to directory module

Bean: <this-task-id>"
```
