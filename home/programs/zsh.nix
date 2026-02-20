{ config, lib, pkgs, osConfig, ... }:
with lib;
let
  cfg = config.dotfiles.programs.zsh;
  enableBrewIntegration = osConfig.dotfiles.darwin.brew.enable or false;
in {
  options.dotfiles.programs.zsh = {
    enable = mkEnableOption "Enable zsh";
    extra = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to extra zsh config to include";
    };
  };

  config.programs.zsh = mkIf cfg.enable {
    enable = true;
    dotDir = config.home.homeDirectory + "/.config/zsh";

    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;

    shellAliases = {
      ll = "ls -lah";
      lg = "lazygit";
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "robbyrussell";
    };

    initContent = concatLines [
      (optionalString enableBrewIntegration ''
        eval "$(/opt/homebrew/bin/brew shellenv)"
      '')
      (optionalString (cfg.extra != null) "source ${cfg.extra}")
    ];
  };
}
