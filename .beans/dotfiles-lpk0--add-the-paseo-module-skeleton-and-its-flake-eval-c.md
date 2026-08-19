---
# dotfiles-lpk0
title: Add the paseo module skeleton and its flake eval check
status: todo
type: task
priority: normal
created_at: 2026-08-19T10:56:39Z
updated_at: 2026-08-19T11:00:24Z
parent: dotfiles-ltuq
blocked_by:
    - dotfiles-rdkr
---

**Files:**
- Create: `home/programs/paseo.nix` (auto-imported by `home/default.nix` — no registration needed)
- Modify: `flake.nix` — add `mkPaseoModuleCheck` to the top-level `let`, and a `paseo-module` entry to both systems' `checks`

Test-first: the check goes in before the module, fails because the option does not exist, then the module makes it pass.

The check is deliberately cheap. It passes a **stub** `package` so grepping the rendered unit never drags in paseo's real npm build, which means it runs in seconds on both platforms. All attribute paths below were verified against the pinned home-manager (`4baa8ac`) during planning.

- [ ] **Step 1: Write the failing check**

In `flake.nix`, add to the top-level `let` block, after `mkNixfmtCheck`:

```nix
      # Evaluates a scratch home-manager config with the paseo module enabled and
      # greps the rendered unit/agent for the wiring the module promises. The stub
      # `package` keeps this an eval check: grepping the unit must not drag in
      # paseo's npm build. Defined for both systems even though CI only builds the
      # linux one -- it is what makes the launchd path verifiable on a Mac.
      mkPaseoModuleCheck =
        { pkgs, system }:
        let
          isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
          hm = mkHomeManagerSystem {
            inherit system;
            user = "paseo-check";
            directory = if isDarwin then "/Users/paseo-check" else "/home/paseo-check";
            home = {
              home.stateVersion = "23.05";
              # Keeps the eval cheap -- none of the base programs are relevant here.
              dotfiles.profiles.base = false;
              dotfiles.programs.paseo = {
                enable = true;
                package = pkgs.writeShellScriptBin "paseo-server" "";
                listenAddress = "0.0.0.0";
                port = 7171;
              };
            };
          };
          # home-manager materialises user units through xdg.configFile; on darwin
          # the agent plist is not exposed as a file, so serialise the evaluated
          # config instead.
          unit =
            if isDarwin then
              pkgs.writeText "paseo-agent.json" (
                builtins.toJSON hm.config.launchd.agents.paseo.config
              )
            else
              hm.config.xdg.configFile."systemd/user/paseo.service".source;
          launcher =
            if isDarwin then
              builtins.head hm.config.launchd.agents.paseo.config.ProgramArguments
            else
              builtins.head hm.config.systemd.user.services.paseo.Service.ExecStart;
        in
        pkgs.runCommandLocal "paseo-module-check" { } ''
          set -euo pipefail
          grep -F '0.0.0.0:7171' ${unit}
          grep -F -- '--no-relay' ${launcher}
          grep -F '/.local/bin' ${launcher}
          touch $out
        '';
```

Then add it to both systems in the `checks` attribute:

```nix
          aarch64-darwin =
            self.packages.aarch64-darwin
            // darwinPkgs.dotfiles.internal.rustChecks
            // {
              nixfmt = mkNixfmtCheck darwinPkgs;
              paseo-module = mkPaseoModuleCheck {
                pkgs = darwinPkgs;
                system = "aarch64-darwin";
              };
            };
          x86_64-linux =
            self.packages.x86_64-linux
            // linuxPkgs.dotfiles.internal.rustChecks
            // {
              nixfmt = mkNixfmtCheck linuxPkgs;
              paseo-module = mkPaseoModuleCheck {
                pkgs = linuxPkgs;
                system = "x86_64-linux";
              };
            };
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link 2>&1 | tail -5`
Expected: FAIL with `The option 'dotfiles.programs.paseo' does not exist`.

- [ ] **Step 3: Write the module**

Create `home/programs/paseo.nix`:

```nix
# Paseo, a self-hosted daemon for AI coding agents, as a *user* service --
# systemd user unit on Linux, launchd agent on macOS. Upstream ships a NixOS
# system module only.
#
# Note for Linux hosts: a systemd user service is stopped at logout unless the
# system config sets `users.users.<name>.linger = true`. home-manager cannot set
# that; it is a downstream system-config requirement.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.programs.paseo;

  systemPaths =
    if pkgs.stdenv.isDarwin then
      [
        "/etc/profiles/per-user/${config.home.username}/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ]
    else
      [
        "/etc/profiles/per-user/${config.home.username}/bin"
        "/run/current-system/sw/bin"
        "/run/wrappers/bin"
        "/nix/var/nix/profiles/default/bin"
      ];

  # `~/.local/bin` is unconditional and first among the defaults: the claude-code
  # and codex modules install their wrappers there via home.activation, and no Nix
  # profile directory covers it. Agents the daemon spawns need them on PATH --
  # this is the `mkForce` that downstream system configs would otherwise carry.
  servicePath = lib.concatStringsSep ":" (
    lib.unique (
      [ "${config.home.homeDirectory}/.local/bin" ]
      ++ config.home.sessionPath
      ++ [ "${config.home.profileDirectory}/bin" ]
      ++ systemPaths
    )
  );

  launcher = pkgs.writeShellScript "paseo-launcher" ''
    set -euo pipefail

    export PATH="${servicePath}"

    # home-manager has no systemd.tmpfiles equivalent; upstream's NixOS module
    # creates PASEO_HOME with the same 0700 mode.
    mkdir -p "$PASEO_HOME"
    chmod 700 "$PASEO_HOME"

    exec ${cfg.package}/bin/paseo-server --no-relay
  '';

  serviceEnv = {
    PASEO_HOME = cfg.dataDir;
    PASEO_LISTEN = "${cfg.listenAddress}:${toString cfg.port}";
  };
in
{
  options.dotfiles.programs.paseo = {
    enable = lib.mkEnableOption "Enable the paseo daemon as a user service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dotfiles.paseo;
      defaultText = lib.literalExpression "pkgs.dotfiles.paseo";
      description = "The paseo package to run.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.paseo";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.paseo"'';
      description = "Directory holding paseo's state, exported as PASEO_HOME.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the daemon binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6767;
      description = "Port the daemon listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The CLI, so `paseo ...` works interactively and not just as a daemon.
    home.packages = [ cfg.package ];

    launchd.agents.paseo = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${launcher}" ];
        KeepAlive = true;
        RunAtLoad = true;
        EnvironmentVariables = serviceEnv;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/paseo.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/paseo.log";
      };
    };

    systemd.user.services.paseo = lib.mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "Paseo - self-hosted daemon for AI coding agents";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${launcher}";
        # home-manager types this as `listOf str`, so the attrset is rendered
        # here. systemd unquotes Environment= shell-style, hence escapeShellArg.
        Environment = lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") serviceEnv;
        Restart = "on-failure";
        RestartSec = 5;
        # Upstream's server handles SIGTERM with a 10s internal timeout.
        KillSignal = "SIGTERM";
        TimeoutStopSec = 15;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
```

- [ ] **Step 4: Run the check on both systems to verify it passes**

Run: `nix build .#checks.aarch64-darwin.paseo-module --no-link`
Expected: PASS (no output, exit 0). This exercises the launchd path.

Run: `nix eval --raw .#checks.x86_64-linux.paseo-module.drvPath`
Expected: a `/nix/store/...paseo-module-check.drv` path. This proves the systemd path evaluates; building it needs a linux builder, and CI covers that.

- [ ] **Step 5: Format check**

Run: `nixfmt --check flake.nix home/programs/paseo.nix`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add flake.nix home/programs/paseo.nix
git commit -m "home/programs/paseo: add module with systemd and launchd services

Bean: dotfiles-lpk0"
```

## Note: a second eval check may already exist

Bean dotfiles-d6t2 (separate epic) adds a `home-eval` check with `mkHomeEvalCheck` in the same `let` block and a `checks/home-eval.nix` module. If that has already landed when you pick this up:

- Put `mkPaseoModuleCheck` beside `mkHomeEvalCheck`, not in place of it. They answer different questions — `home-eval` forces assertions broadly, this one greps the rendered unit for specific wiring.
- Do not move this check's scratch config into `checks/home-eval.nix`. Enabling paseo there would pull `pkgs.dotfiles.paseo` into that check's closure, which is exactly what the stub `package` here avoids.
