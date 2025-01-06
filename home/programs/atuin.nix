{ config, lib, ... }:
with lib;
let cfg = config.dotfiles.programs.atuin;
in {
  options.dotfiles.programs.atuin = { enable = mkEnableOption "Enable atuin"; };

  config.programs.atuin = mkIf cfg.enable {
    enable = true;
    enableZshIntegration = true; # TODO: Should follow zsh enablement?
    settings = { enter_accept = false; };
  };
}
