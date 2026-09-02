{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.programs.paseo;

  configFormat = pkgs.formats.json { };

  # home.sessionPath is written for a shell, so an entry may spell out $HOME (the
  # claude-code and codex modules both contribute "$HOME/.local/bin"). Neither
  # systemd's Environment= nor launchd's EnvironmentVariables expands that, so
  # resolve it here — which also lets lib.unique collapse those entries against
  # the explicit ~/.local/bin below.
  expandHome =
    lib.replaceStrings
      [ "\${HOME}" "$HOME" ]
      [
        config.home.homeDirectory
        config.home.homeDirectory
      ];

  # launchd agents get no login-shell environment, and a systemd user unit has no
  # inherited PATH worth the name either, so the daemon needs an explicit one.
  # home.sessionPath is carried in because it is the config's own answer to "what
  # belongs on PATH" — it otherwise reaches only shells, via hm-session-vars.sh in
  # .zshenv, and agents spawned by the daemon never see it. A shell-level fix
  # cannot cover them: claude-code snapshots its own PATH and re-exports it over
  # whatever .zshenv computed.
  #
  # ~/.local/bin is still listed explicitly because that is where the claude-code
  # module installs its `claude` wrapper — without it the daemon cannot spawn
  # agents at all, and that must not depend on another module having contributed a
  # sessionPath entry.
  servicePath = lib.concatStringsSep ":" (
    lib.unique (
      cfg.extraPath
      ++ map expandHome config.home.sessionPath
      ++ [
        "${config.home.homeDirectory}/.local/bin"
        "${config.home.homeDirectory}/.nix-profile/bin"
        "${config.home.homeDirectory}/.local/state/nix/profile/bin"
        "/etc/profiles/per-user/${config.home.username}/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [ "/run/wrappers/bin" ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        "/opt/homebrew/bin"
        "/usr/local/bin"
      ]
      ++ [
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ]
    )
  );

  serviceEnv = {
    PASEO_HOME = cfg.dataDir;
    PASEO_LISTEN = "${cfg.listenAddress}:${toString cfg.port}";
    PATH = servicePath;
  }
  // lib.optionalAttrs (cfg.hostnames == true) { PASEO_HOSTNAMES = "true"; }
  // lib.optionalAttrs (lib.isList cfg.hostnames && cfg.hostnames != [ ]) {
    PASEO_HOSTNAMES = lib.concatStringsSep "," cfg.hostnames;
  }
  // cfg.environment;

  # Relay is never enabled: upstream's default dials app.paseo.sh, and there is
  # no option here to turn that on by accident.
  serverArgs = [ "--no-relay" ];

  serverCommand = "${cfg.package}/bin/paseo-server";

  # Neither systemd's Environment= nor launchd's EnvironmentVariables performs
  # command substitution, so anything resolved at runtime has to be applied by
  # something running between the unit and the server.
  launcher = pkgs.writeShellScript "paseo-launcher" ''
    set -euo pipefail

    # Assigning first, rather than piping into the loop, is what makes a failing
    # command fatal: `set -e` does not fire on the left-hand side of a pipe, and
    # a daemon that came up missing its hostname or its password would present
    # as a networking fault rather than a startup failure.
    environment="$(${cfg.environmentCommand})"

    while IFS= read -r line; do
      case "$line" in
        "" | \#*) continue ;;
        [A-Za-z_]*=*) export "$line" ;;
        *)
          echo "paseo: environmentCommand emitted a line that is not NAME=value: $line" >&2
          exit 1
          ;;
      esac
    done <<< "$environment"

    exec ${serverCommand} ${lib.escapeShellArgs serverArgs}
  '';

  startCommand =
    if cfg.environmentCommand != null then [ "${launcher}" ] else [ serverCommand ] ++ serverArgs;

  dataDirRelative = lib.removePrefix "${config.home.homeDirectory}/" cfg.dataDir;
in
{
  options.dotfiles.programs.paseo = {
    enable = lib.mkEnableOption "Enable paseo (the `paseo` CLI and `paseo-server` daemon)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dotfiles.paseo;
      defaultText = lib.literalExpression "pkgs.dotfiles.paseo";
      description = "The paseo daemon package.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.paseo";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.paseo"'';
      description = ''
        Directory for paseo state (`PASEO_HOME`): agent data, config, and logs.

        Leave this at the default if you also use the desktop app. The app
        resolves `PASEO_HOME` from your login shell, and it only recognises (and
        attaches to) an already-running daemon that shares its state directory —
        point them at different directories and you get two daemons fighting over
        the port.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6767;
      description = "Port for the paseo daemon to listen on.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address for the paseo daemon to bind to.";
    };

    hostnames = lib.mkOption {
      type = lib.types.either (lib.types.enum [ true ]) (lib.types.listOf lib.types.str);
      default = [ ];
      example = [ ".example.com" ];
      description = ''
        Hostnames the daemon accepts in the Host header (DNS rebinding
        protection). Localhost and IP addresses are always allowed. A leading dot
        matches a domain and its subdomains. `true` allows any host.
      '';
    };

    settings = lib.mkOption {
      type = configFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          daemon.mcp = {
            enabled = true;
            injectIntoAgents = false;
          };
          log.file.level = "info";
        }
      '';
      description = ''
        Declarative content for `$PASEO_HOME/config.json`, linked from the store.

        Leave this empty (the default) to let the daemon create and own the file.
        That is the right choice if you want `paseo daemon set-password`: setting
        `settings` makes the file a store symlink, so a password written at
        runtime is discarded at the next home-manager activation.

        The schema is `PersistedConfigSchema` in
        `packages/server/src/server/persisted-config.ts` upstream.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        BROWSER = "wsl-open";
      };
      description = ''
        Extra environment variables for the daemon, applied over the computed
        ones. Agent processes the daemon spawns inherit these. Only
        `environmentCommand` takes precedence over this.
      '';
    };

    environmentCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression ''
        "''${pkgs.writeShellScript "paseo-env" "echo PASEO_HOSTNAMES=$(get-fqdn)"}"
      '';
      description = ''
        Command run at daemon start whose stdout is parsed as `NAME=value` lines
        and exported into the daemon's environment. For values that are only
        knowable at runtime: a cloud instance's own FQDN, or a secret that must
        not be written to the world-readable store.

        Blank lines and `#` comments are ignored. Values are taken verbatim to
        end of line -- no quote stripping, no expansion -- and a line that is
        not `NAME=value` aborts the start. A non-zero exit aborts the start too,
        so a failed lookup cannot bring the daemon up half-configured.

        Applied after the unit environment, so it overrides both the computed
        `PASEO_*` variables and `environment`. Resolved against the daemon's
        PATH, so a bare command name works; a store path avoids depending on it.
      '';
    };

    extraPath = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Directories prepended to the daemon's PATH.";
    };

    service = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run the daemon as a user service: a launchd agent on Darwin, a systemd
          user service on Linux. On a headless Linux host the user needs lingering
          enabled (`users.users.<name>.linger = true`) or the daemon stops with
          the last session.
        '';
      };

      logFile = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/Library/Logs/paseo.log";
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/Library/Logs/paseo.log"'';
        description = "Where the launchd agent writes stdout and stderr (Darwin only).";
      };
    };

    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install the Paseo desktop app. Independent of `enable`: this is the
          signed upstream release bundle, so a machine that only wants the app
          builds nothing.

          The app bundles its own daemon but attaches to an already-running one
          sharing its `PASEO_HOME`, so it is safe to enable alongside
          `service.enable`. Do not use the app's "Install CLI" button — it writes
          a shim to ~/.local/bin that shadows the Nix `paseo` and edits ~/.zshrc,
          which home-manager owns.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = cfg.package.desktop;
        defaultText = lib.literalExpression "pkgs.dotfiles.paseo.desktop";
        description = "The paseo desktop app package.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.service.enable -> cfg.enable;
          message = "dotfiles.programs.paseo.service.enable requires dotfiles.programs.paseo.enable (the unit runs paseo-server).";
        }
        {
          assertion = cfg.desktop.enable -> pkgs.stdenv.hostPlatform.isDarwin;
          message = "dotfiles.programs.paseo.desktop.enable is only supported on Darwin.";
        }
        {
          assertion = (cfg.settings == { }) || (lib.hasPrefix "${config.home.homeDirectory}/" cfg.dataDir);
          message = "dotfiles.programs.paseo.settings requires dataDir to be inside the home directory, since it is written with home.file.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      home.packages = [ cfg.package ];

      # The daemon writes config.json only when it is absent, and its chmod to
      # 0600 is best-effort (it swallows the EPERM from a root-owned store file),
      # so a store symlink is safe here.
      home.file = lib.mkIf (cfg.settings != { }) {
        "${dataDirRelative}/config.json".source = configFormat.generate "paseo-config.json" cfg.settings;
      };

      # home.file creates the parent at 0755; the daemon expects 0700 and only
      # enforces it on paths it writes itself.
      home.activation.paseoDataDirMode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p ${lib.escapeShellArg cfg.dataDir}
        run chmod 700 ${lib.escapeShellArg cfg.dataDir}
      '';
    })

    (lib.mkIf cfg.service.enable {
      launchd.agents.paseo = lib.mkIf pkgs.stdenv.isDarwin {
        enable = true;
        config = {
          ProgramArguments = startCommand;
          EnvironmentVariables = serviceEnv;
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = cfg.service.logFile;
          StandardErrorPath = cfg.service.logFile;
        };
      };

      systemd.user.services.paseo = lib.mkIf pkgs.stdenv.isLinux {
        Unit = {
          Description = "Paseo - self-hosted daemon for AI coding agents";
          After = [ "network.target" ];
        };
        Service = {
          ExecStart = lib.concatStringsSep " " startCommand;
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") serviceEnv;
          Restart = "on-failure";
          RestartSec = 5;
          # The server handles SIGTERM with a 10s timeout of its own.
          KillSignal = "SIGTERM";
          TimeoutStopSec = 15;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    # Deliberately not gated on cfg.enable: the desktop app is a separate,
    # build-free artifact. mkIf is lazy in its content, so cfg.desktop.package
    # (which throws on non-Darwin) is never forced on Linux.
    (lib.mkIf cfg.desktop.enable {
      home.packages = [ cfg.desktop.package ];
    })
  ];
}
