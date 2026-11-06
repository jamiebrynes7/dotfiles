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

  determinate = options ? determinate && config.determinate.enable;

  userProfileDirs = lib.concatMap (name: [
    "${config.users.users.${name}.home}/.local/state/nix/profiles"
    "/nix/var/nix/profiles/per-user/${name}"
  ]) (lib.attrNames config.home-manager.users);
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    systemd.services.dotfiles-nix-gc = {
      description = "Prune Nix profiles, collect garbage and optimise the store";
      path = [ config.nix.package ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe gc)
            (toString cfg.keepGenerations)
            "/nix/var/nix/profiles"
            "/nix/var/nix/profiles/per-user/root"
          ]
          ++ userProfileDirs
        );
        Nice = 19;
        IOSchedulingClass = "idle";
      };
      startAt = "Sun 03:15";
    };
    systemd.timers.dotfiles-nix-gc.timerConfig.Persistent = true;

    # Determinate Nixd runs its own collector, which would otherwise race this
    # job and ignore `keepGenerations`. Its NixOS module has no option for it and
    # only writes this file for `edgeCacheSubstituters`, so take the file over
    # and carry that setting across.
    environment.etc."determinate/config.json" = lib.mkIf determinate {
      text = lib.mkForce (
        builtins.toJSON (
          {
            garbageCollector.strategy = "disabled";
          }
          // lib.optionalAttrs (config.determinate.edgeCacheSubstituters != null) {
            inherit (config.determinate) edgeCacheSubstituters;
          }
        )
      );
    };
  };
}
