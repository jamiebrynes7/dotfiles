{ config, lib, ... }:
with lib;
let
  cfg = config.dotfiles.darwin.brew;

  noQuarantine = name: {
    inherit name;
    args = { no_quarantine = true; };
  };

  default = [
    (noQuarantine "alacritty")
    "bartender"
    "cleanshot"
    "raycast"
    "rectangle"
    "spotify"
  ];
  social = [ "discord" "whatsapp" ];
  productivity = [ "1password" "notion-calendar" "obsidian" "todoist" ];
  gaming = [ "steam" ];
in {
  options.dotfiles.darwin.brew = {
    enable = mkEnableOption "Enable brew management through Nix";
    profiles = {
      default = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the default set of brew casks";
      };
      social = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the social set of brew casks.";
      };
      productivity = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the productivity set of brew casks.";
      };
      gaming = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the gaming set of brew casks.";
      };
    };
  };

  config.homebrew = mkIf cfg.enable {
    enable = true;
    casks = mkMerge [
      (mkIf cfg.profiles.default default)
      (mkIf cfg.profiles.social social)
      (mkIf cfg.profiles.productivity productivity)
      (mkIf cfg.profiles.gaming gaming)
    ];
  };
}
