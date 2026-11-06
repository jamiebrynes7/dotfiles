# Standalone home-manager only: under nix-darwin and NixOS the system job
# already prunes every home-manager user's profiles.
#
# Runs unprivileged, so it can only collect what no root references; on a
# Determinate machine Determinate Nixd's own collector keeps running alongside.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.nix.gc;
  gc = pkgs.callPackage ./script.nix { };

  args = [
    (lib.getExe gc)
    (toString cfg.keepGenerations)
    "${config.xdg.stateHome}/nix/profiles"
    "/nix/var/nix/profiles/per-user/${config.home.username}"
  ];
  path = lib.concatStringsSep ":" [
    "${config.home.profileDirectory}/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
  ];
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        launchd.agents.dotfiles-nix-gc = {
          enable = true;
          config = {
            ProgramArguments = args;
            EnvironmentVariables.PATH = path;
            StartCalendarInterval = [
              {
                Weekday = 0;
                Hour = 3;
                Minute = 15;
              }
            ];
            ProcessType = "Background";
            LowPriorityIO = true;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/dotfiles-nix-gc.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/dotfiles-nix-gc.log";
          };
        };
      })

      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        systemd.user.services.dotfiles-nix-gc = {
          Unit.Description = "Prune Nix profiles, collect garbage and optimise the store";
          Service = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs args;
            Environment = "PATH=${path}";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
        systemd.user.timers.dotfiles-nix-gc = {
          Unit.Description = "Weekly Nix profile pruning and garbage collection";
          Timer = {
            OnCalendar = "Sun 03:15";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      })
    ]
  );
}
