---
# dotfiles-g31z
title: Add extraSessionPaths option and migrate claude-code
status: completed
type: task
priority: normal
created_at: 2026-06-04T10:10:46Z
updated_at: 2026-06-04T10:21:01Z
parent: dotfiles-e8zz
---

**Files:**
- Modify: `home/programs/zsh.nix`
- Modify: `home/programs/claude-code/default.nix` (the PATH export at lines ~163-166)

Context: `home/programs/zsh.nix` uses `with lib;` and assigns `config.programs.zsh = mkIf cfg.enable { ... }`. Add `home.sessionPath` as a sibling `config.home.sessionPath` binding (dotted keys merge — do NOT restructure the existing `config.programs.zsh` block). `claude-code/default.nix` currently puts `~/.local/bin` on PATH with a raw `programs.zsh.envExtra` export; replace that with a contribution to the new option.

- [x] **Step 1: Add the option to `home/programs/zsh.nix`**

Inside `options.dotfiles.programs.zsh = { ... }`, after the `extra` option:

```nix
    extraSessionPaths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description =
        "Extra entries appended to PATH via home.sessionPath (de-duplicated).";
    };
```

- [x] **Step 2: Wire it into `home.sessionPath` in `home/programs/zsh.nix`**

After the closing of the `config.programs.zsh = mkIf cfg.enable { ... };` block (as a new sibling line, still inside the module attrset):

```nix
  config.home.sessionPath = mkIf cfg.enable (unique cfg.extraSessionPaths);
```

`unique` and `mkIf` are in scope via `with lib;`. The module system concatenates `extraSessionPaths` contributions from all modules; `unique` collapses duplicates so each entry lands in PATH once.

- [x] **Step 3: Migrate `home/programs/claude-code/default.nix`**

Replace this block:

```nix
    # Add to PATH
    programs.zsh.envExtra = ''
      export PATH="$HOME/.local/bin:$PATH"
    '';
```

with:

```nix
    # Ensure the wrapper dir is on PATH (de-duplicated via the zsh module).
    dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ];
```

- [x] **Step 4: Format both files**

Run: `nixfmt home/programs/zsh.nix home/programs/claude-code/default.nix`
Expected: no errors; files reformatted in place if needed.

- [x] **Step 5: Build/eval the flake**

Run: `nix flake check`
Expected: PASS (evaluation succeeds; no assertion or type errors for the new option).

- [ ] **Step 6: Post-switch verification (run on a host after `darwin-rebuild`/`home-manager switch`)**

```bash
# ~/.local/bin appears on PATH exactly once
echo "$PATH" | tr ':' '
' | grep -c "/.local/bin$"   # expect: 1
which claude                                            # expect: ~/.local/bin/claude
```

- [ ] **Step 7: Commit**

```bash
git add home/programs/zsh.nix home/programs/claude-code/default.nix
git commit -m "$(cat <<'MSG'
home/programs/zsh: add de-duplicated extraSessionPaths option

Migrate claude-code off its raw envExtra PATH export onto the shared
option so multiple modules can request ~/.local/bin on PATH without
duplicating the entry.

Bean: dotfiles-e8zz
MSG
)"
```

## Summary of Changes

Added a `dotfiles.programs.zsh.extraSessionPaths` option (`listOf str`, default `[]`) to `home/programs/zsh.nix`, wired into home-manager's `home.sessionPath` via `lib.unique` as a sibling `config.home.sessionPath` binding. Any module can now request a PATH entry and `lib.unique` guarantees it appears once (home-manager does not dedup sessionPath itself — verified).

Migrated `home/programs/claude-code/default.nix` off its raw `programs.zsh.envExtra` PATH export onto `dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ]`. Behaviour preserved: `~/.local/bin` is prepended to PATH exactly once, so the claude wrapper still shadows same-named binaries.

Validated with `nixfmt` + `nix flake check` (passes). Subagent review confirmed $HOME expansion and prepend semantics match the old export; user review requested removing an inline comment (done).
