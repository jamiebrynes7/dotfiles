{ config, lib, ... }:
with lib;
let cfg = config.dotfiles.darwin;
in {
  imports = [ ./brew.nix ];

  options.dotfiles.darwin = {
    primaryUser = mkOption {
      type = types.str;
      description = "The primary user of the system.";
    };
  };

  config = {
    # Needed to ensure that the nix installation works as expected.
    # May need to bootstrap the first invocation.
    nix.extraOptions = ''
      experimental-features = nix-command flakes auto-allocate-uids
    '';

    system = {
      primaryUser = cfg.primaryUser;

      # Remap caps-lock to escape.
      keyboard = {
        enableKeyMapping = true;
        remapCapsLockToEscape = true;
      };

      # Disable hot corners
      defaults.dock = {
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
      };
    };

    # Allow touch ID for sudo authentication.
    security.pam.services.sudo_local.touchIdAuth = true;
  };

}
