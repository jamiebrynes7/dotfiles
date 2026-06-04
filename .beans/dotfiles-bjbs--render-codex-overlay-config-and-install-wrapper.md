---
# dotfiles-bjbs
title: Render codex overlay config and install wrapper
status: todo
type: task
priority: normal
created_at: 2026-06-04T10:11:12Z
updated_at: 2026-06-04T10:11:42Z
parent: dotfiles-kan2
blocked_by:
    - dotfiles-g31z
---

**Files:**
- Modify: `home/programs/codex.nix`

Context: the module uses `with lib;` and has `let cfg = config.dotfiles.programs.codex; aiSkills = ...; skills = ...; in`. Args already include `pkgs`. Today it sets `home.packages = [ pkgs.dotfiles.codex ];` and a `home.file` attrset with `.codex/AGENTS.md` plus `skills.files`. Mirror the `home/programs/claude-code/default.nix` wrapper pattern (writeShellScript + `home.activation` `install -m755` into `~/.local/bin`). Depends on the zsh `extraSessionPaths` option (sibling task) already existing.

- [ ] **Step 1: Add the `hooks` option**

Inside `options.dotfiles.programs.codex = { ... }`, after `skillsDirs`:

```nix
    hooks = mkOption {
      type = types.bool;
      default = true;
      description =
        "Enable Codex lifecycle hooks ([features].hooks) via the dotfiles profile overlay.";
    };
```

- [ ] **Step 2: Add `let` bindings for the rendered config and wrapper**

In the `let ... in` block (after `skills = ...;`):

```nix
  codexConfig = (pkgs.formats.toml { }).generate "codex-dotfiles.toml" {
    features.hooks = cfg.hooks;
  };
  codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
    exec ${pkgs.dotfiles.codex}/bin/codex --profile dotfiles "$@"
  '';
```

- [ ] **Step 3: Deploy the overlay file and drop the direct package**

Remove these lines:

```nix
    # The codex binary is unbundled: it shells out to an ambient `rg` and, on
    # Linux only, `bubblewrap` for sandboxing. Neither is added here — codex
    # relies on those being on PATH (the base profile already provides ripgrep).
    home.packages = [ pkgs.dotfiles.codex ];
```

Add `.codex/dotfiles.config.toml` to the existing `home.file` attrset so it reads:

```nix
    home.file = skills.files // {
      ".codex/AGENTS.md".source = ../lib/ai/global-instructions.md;
      ".codex/dotfiles.config.toml".source = codexConfig;
    };
```

(Codex is now delivered via the wrapper, whose closure references `pkgs.dotfiles.codex`, so it is still realised. ripgrep still comes from the base profile.)

- [ ] **Step 4: Install the wrapper and contribute to PATH**

Inside the `config = mkIf cfg.enable { ... }` block, alongside the existing `dotfiles.programs.codex.skillsDirs` line, add the PATH contribution:

```nix
    dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ];
```

And add the activation entry (e.g. after the `home.file` attrset):

```nix
    home.activation.codexStableLink =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        install -m755 ${codexWrapper} "$HOME/.local/bin/codex"
      '';
```

- [ ] **Step 5: Format the file**

Run: `nixfmt home/programs/codex.nix`
Expected: no errors.

- [ ] **Step 6: Build/eval the flake**

Run: `nix flake check`
Expected: PASS.

- [ ] **Step 7: Confirm the build covers the rendered config**

`nix flake check` (Step 6) already evaluates the module and realises `codexConfig` (it is referenced by `home.file`), so a green check means the TOML rendered without error. The actual file *content* (`[features]` / `hooks = true`) and symlink-ness are verified post-switch in Step 8 — there is no host-independent way to inspect the deployed file from this repo alone.

- [ ] **Step 8: Post-switch verification (run on a host after switch)**

```bash
test -L ~/.codex/dotfiles.config.toml && echo "symlink OK"      # expect: symlink OK
grep -A1 '\[features\]' ~/.codex/dotfiles.config.toml           # expect: hooks = true
test -L ~/.codex/config.toml && echo "CONFIG IS SYMLINK (bad)" || echo "config.toml untouched"  # expect: untouched
which codex                                                     # expect: ~/.local/bin/codex
grep -- '--profile dotfiles' "$(which codex)"                   # expect: the exec line
```

Then flip `dotfiles.programs.codex.hooks = false`, rebuild, and confirm the overlay flips to `hooks = false` — proving the knob flows end to end.

- [ ] **Step 9: Commit**

```bash
git add home/programs/codex.nix
git commit -m "$(cat <<'MSG'
home/programs/codex: manage config via dotfiles profile overlay

Render ~/.codex/dotfiles.config.toml from pkgs.formats.toml and wrap the
codex binary to always exec with --profile dotfiles, so managed config
overlays config.toml without clobbering Codex-written state. Adds a
hooks bool knob ([features].hooks, default true) as the first setting.

Bean: dotfiles-kan2
MSG
)"
```
