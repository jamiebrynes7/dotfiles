{ config, lib, pkgs, ... }:
with lib;
let cfg = config.dotfiles.profiles;
in {
  options.dotfiles.profiles = {
    base = mkOption {
      type = types.bool;
      default = true;
    };
    desktop = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkMerge [
    (mkIf cfg.base {
      dotfiles.programs = {
        atuin.enable = true;
        bat.enable = true;
        direnv.enable = true;
        git.enable = true;
        nvim.enable = true;
        zsh.enable = true;
      };

      home.packages = with pkgs; [ fzf lazygit jq ripgrep ];
    })
    (mkIf cfg.desktop {
      dotfiles.programs = {
        alacritty.enable = true;
        zellij.enable = true;
      };
    })
  ];
}
