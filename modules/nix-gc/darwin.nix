{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.nix.gc;
  gc = pkgs.callPackage ./script.nix { };

  # Determinate takes over Nix by way of `nix.enable = false`, whether through
  # its own nix-darwin module or by hand, so that is the signal.
  determinate = !config.nix.enable;
  determinateModule = options ? determinateNix && config.determinateNix.enable;

  userProfileDirs = lib.concatMap (name: [
    "${config.users.users.${name}.home}/.local/state/nix/profiles"
    "/nix/var/nix/profiles/per-user/${name}"
  ]) (lib.attrNames config.home-manager.users);
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        launchd.daemons.dotfiles-nix-gc.serviceConfig = {
          ProgramArguments = [
            (lib.getExe gc)
            (toString cfg.keepGenerations)
            "/nix/var/nix/profiles"
            "/nix/var/nix/profiles/per-user/root"
          ]
          ++ userProfileDirs;
          # With `nix.enable = false` nix-darwin installs no Nix of its own, so
          # fall back to where Determinate and the upstream installer put it.
          EnvironmentVariables.PATH = lib.concatStringsSep ":" (
            lib.optional config.nix.enable "${config.nix.package}/bin"
            ++ [
              "/nix/var/nix/profiles/default/bin"
              "/usr/local/bin"
            ]
          );
          StartCalendarInterval = [
            {
              Weekday = 0;
              Hour = 3;
              Minute = 15;
            }
          ];
          ProcessType = "Background";
          LowPriorityIO = true;
          StandardOutPath = "/var/log/dotfiles-nix-gc.log";
          StandardErrorPath = "/var/log/dotfiles-nix-gc.log";
        };
      }

      # Determinate Nixd runs its own collector, which would otherwise race this
      # job and ignore `keepGenerations`.
      (lib.optionalAttrs (options ? determinateNix) {
        determinateNix.determinateNixd.garbageCollector.strategy = "disabled";
      })
      (lib.mkIf (determinate && !determinateModule) {
        environment.etc."determinate/config.json".text = builtins.toJSON {
          garbageCollector.strategy = "disabled";
        };
      })
    ]
  );
}
