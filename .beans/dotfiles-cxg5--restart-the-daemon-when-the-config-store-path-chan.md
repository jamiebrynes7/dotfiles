---
# dotfiles-cxg5
title: Restart the daemon when the config store path changes
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:29:14Z
updated_at: 2026-09-21T17:30:08Z
parent: dotfiles-eii4
blocked_by:
    - dotfiles-t4ve
---

**Files:**
- Modify: `home/programs/paseo.nix:109` — add `restartDaemon` to the `let` block
- Modify: `home/programs/paseo.nix` — add `home.activation.paseoRestart` inside the `lib.mkIf cfg.service.enable` block

Why this is needed: home-manager reloads a launchd agent only when the plist changes, and nothing in the unit depends on `config.json`. The daemon reads plugins once, in `start()` (`plugins/index.ts:131`); `paseo reload` re-reads the file but does not re-activate plugin source entries, and `reloadPlugin` uses the in-memory path. So a plugin bump — a new store path in the config — takes effect only on a restart.

Depends on the move-aside task: this entry reads the `paseoOldConfigTarget` variable that one sets.

- [ ] **Step 1: Add the platform-specific restart to the `let` block**

```nix
  restartDaemon =
    if pkgs.stdenv.isDarwin then
      ''
        paseoAgent="gui/$(id -u)/org.nix-community.home.paseo"
        if launchctl print "$paseoAgent" >/dev/null 2>&1; then
          noteEcho "paseo: config changed, restarting the daemon"
          run launchctl kickstart -k "$paseoAgent"
        fi
      ''
    else
      ''
        if systemctl --user is-active --quiet paseo.service; then
          noteEcho "paseo: config changed, restarting the daemon"
          run systemctl --user try-restart paseo.service
        fi
      '';
```

The label is home-manager's own for `launchd.agents.paseo` — the same `org.nix-community.home.<name>` shape as the installed `org.nix-community.home.beans-daemon.plist`.

- [ ] **Step 2: Add the activation entry**

In the `lib.mkIf cfg.service.enable` element:

```nix
      home.activation.paseoRestart = lib.hm.dag.entryAfter [ "writeBoundary" "paseoDataDirMode" ] ''
        paseoNewConfigTarget="$(readlink ${lib.escapeShellArg "${cfg.dataDir}/config.json"} 2>/dev/null || true)"
        # Compare rather than always restarting: an unrelated switch must not kill the
        # agent sessions running inside the daemon.
        if [ "''${paseoOldConfigTarget-}" != "$paseoNewConfigTarget" ]; then
        ${restartDaemon}
        fi
      '';
```

Note the `''${paseoOldConfigTarget-}` escape: inside a Nix indented string `${` starts interpolation, and `''$` emits a literal `$`. The `-` default expansion matters because the activation script runs under `set -u` and the variable is unset when the module is enabled without the backup entry having assigned it.

- [ ] **Step 3: Format**

Run: `nixfmt home/programs/paseo.nix`

- [ ] **Step 4: Verify the generated script**

```bash
nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    hm = flake.lib.mkHomeManagerSystem {
      system = builtins.currentSystem;
      user = "test";
      directory = "/home/test";
      home = { ... }: {
        home.stateVersion = "25.05";
        dotfiles.profiles.base = false;
        dotfiles.programs.paseo = { enable = true; service.enable = true; };
      };
    };
  in hm.config.home.activation.paseoRestart.data
'
```

Expected on macOS: the script reads `readlink /home/test/.paseo/config.json`, compares against `${paseoOldConfigTarget-}` (a literal `$`, not an interpolated empty string — if the comparison reads `[ "" != ... ]` the escape is wrong), and calls `launchctl kickstart -k`.

- [ ] **Step 5: Verify it is absent without `service.enable`**

Run the same command with `service.enable` removed.

Expected: evaluation fails with a missing-attribute error for `paseoRestart` — there is no unit to restart, so the entry should not exist.

- [ ] **Step 6: Commit**

```bash
git add home/programs/paseo.nix
git commit -m "home/programs/paseo: restart the daemon when config.json changes" -m "Bean: dotfiles-cxg5"
```
