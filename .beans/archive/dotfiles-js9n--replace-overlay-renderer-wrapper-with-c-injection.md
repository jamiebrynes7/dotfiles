---
# dotfiles-js9n
title: Replace overlay renderer + wrapper with -c injection
status: completed
type: task
priority: normal
created_at: 2026-06-04T13:51:35Z
updated_at: 2026-06-04T14:06:59Z
parent: dotfiles-16g2
---

**Files:**
- Modify: `home/programs/codex/default.nix` (the `let` bindings around lines 16-21 and the `home.file` attrset around lines 62-64)

Goal: render managed settings into `-c` flags and inject them from the wrapper; remove the `--profile` overlay file entirely. The module uses `with lib;` so `lib.`-prefixed calls also resolve unprefixed — keep the `lib.` prefix for clarity.

- [x] **Step 1: Replace the overlay renderer with the managedConfig/configArgs flattener and rewrite the wrapper**

Find this block:

```nix
  codexConfig = (pkgs.formats.toml { }).generate "codex-dotfiles.toml" {
    features.hooks = cfg.enableHooks;
  };
  codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
    exec ${pkgs.dotfiles.codex}/bin/codex --profile dotfiles "$@"
  '';
```

Replace it with:

```nix
  # Managed Codex settings, injected as session-only `-c key=value` overrides
  # (precedence 30). Codex never persists `-c` flags, so there is no managed file
  # for it to clobber. Dotted keys map straight to Codex config paths; bool values
  # render as bare TOML `true`/`false`.
  managedConfig = {
    "features.hooks" = lib.boolToString cfg.enableHooks;
  };
  configArgs = lib.concatStringsSep " "
    (lib.mapAttrsToList (k: v: "-c ${lib.escapeShellArg "${k}=${v}"}") managedConfig);
  codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
    exec ${pkgs.dotfiles.codex}/bin/codex ${configArgs} "$@"
  '';
```

- [x] **Step 2: Remove the overlay file from `home.file`**

Find this entry inside the `home.file = skills.files // { ... }` attrset:

```nix
      ".codex/dotfiles.config.toml".source = codexConfig;
```

Delete that line entirely. The surrounding `".codex/AGENTS.md".source = ...;` line and the `lib.optionalAttrs (mergedHooks != { }) { ".codex/hooks.json" ... }` block stay as-is. home-manager removes the now-orphaned `~/.codex/dotfiles.config.toml` symlink automatically on the next switch.

- [x] **Step 3: Format the file**

Run: `nixfmt home/programs/codex/default.nix`
Expected: exits 0, no diff beyond your edits.

## Summary of Changes

Replaced the broken `--profile dotfiles` overlay-file mechanism with wrapper-injected `-c key=value` session flags in `home/programs/codex/default.nix`:

- Removed the `codexConfig` (`pkgs.formats.toml`) renderer and the `home.file.".codex/dotfiles.config.toml"` deployment.
- Added a dotted-key `managedConfig` attrset and a `configArgs` flattener (`-c ${escapeShellArg "key=value"}`); the wrapper now execs `codex ${configArgs} "$@"` instead of `--profile dotfiles`.
- Updated the `enableHooks` option description and two block comments that referenced the removed overlay/profile.

Validated with `nix flake check` (passes). Subagent review found one stale comment (fixed); user review requested no changes.
