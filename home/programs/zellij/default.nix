{ config, lib, ... }:
with lib;
let cfg = config.dotfiles.programs.zellij;
in {
  options.dotfiles.programs.zellij = {
    enable = mkEnableOption "Enable zellij";
  };

  config = mkIf cfg.enable {
    programs.zellij = {
      enable = true;
      enableZshIntegration = true;
    };

    # TODO: Convert zellij config into Nix expression.
    xdg.configFile."zellij/config.kdl" = { source = ./config.kdl; };
  };
}
