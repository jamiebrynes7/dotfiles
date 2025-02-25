{ config, lib, pkgs, osConfig, ... }:
with lib;
let
  cfg = config.dotfiles.programs.zsh;
  enableBrewIntegration = osConfig.dotfiles.darwin.brew.enable or false;
in {
  options.dotfiles.programs.zsh = { enable = mkEnableOption "Enable zsh"; };

  config.programs.zsh = mkIf cfg.enable {
    enable = true;
    dotDir = ".config/zsh";

    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;

    shellAliases = { ll = "ls -lah"; };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "robbyrussell";
    };

    initExtra =
      mkIf enableBrewIntegration ''eval "$(/opt/homebrew/bin/brew shellenv)"'';
  };
}
