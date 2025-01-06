{ config, lib, ... }:
with lib;
let cfg = config.dotfiles.programs.direnv;
in {
  options.dotfiles.programs.direnv = {
    enable = mkEnableOption "Enable direnv";
  };

  config.programs.direnv = mkIf cfg.enable {
    enable = true;
    nix-direnv.enable = true;
  };
}
