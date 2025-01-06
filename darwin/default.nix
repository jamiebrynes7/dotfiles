{ config, ... }: {
  imports = [ ./brew.nix ];

  config = {
    # Enable nix-daemon for multi-user systems.
    services.nix-daemon.enable = true;

    # Needed to ensure that the nix installation works as expected.
    # May need to bootstrap the first invocation.
    nix.extraOptions = ''
      experimental-features = nix-command flakes auto-allocate-uids
    '';

    system = {
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
    security.pam.enableSudoTouchIdAuth = true;
  };

}
