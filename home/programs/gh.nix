{ config, lib, pkgs, ... }:
with lib;
let cfg = config.dotfiles.programs.gh;
in {
  options.dotfiles.programs.gh = {
    enable = mkEnableOption "Enable GitHub CLI";
  };
  config.programs.gh = mkIf cfg.enable {
    enable = true;
    gitCredentialHelper.enable = true;
  };
}
