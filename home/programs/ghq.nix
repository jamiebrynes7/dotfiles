{ config, lib, pkgs, ... }:
with lib;
let cfg = config.dotfiles.programs.ghq;
in {
  options.dotfiles.programs.ghq = {
    enable = mkEnableOption "Enable ghq";
    root = mkOption {
      type = types.str;
      description = "Root directory for ghq repositories";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [ ghq ];
    programs.zsh.envExtra = ''
      export GHQ_ROOT="${cfg.root}";
    '';
  };
}
