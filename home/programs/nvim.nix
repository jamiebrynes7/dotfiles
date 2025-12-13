{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.nvim;

  gitHubPlugin = repo: ref: rev:
    pkgs.vimUtils.buildVimPlugin {
      pname = "${lib.strings.sanitizeDerivationName repo}";
      version = ref;
      src = builtins.fetchGit {
        url = "https://github.com/${repo}.git";
        ref = ref;
        rev = rev;
      };
    };
in {
  options.dotfiles.programs.nvim = { enable = mkEnableOption "Enable nvim"; };

  config = mkIf cfg.enable {
    programs.neovim = {
      enable = true;

      defaultEditor = true;

      withPython3 = false;
      withRuby = false;

      extraConfig = ''
        :luafile ~/.config/nvim/lua/init.lua
      '';

      plugins = with pkgs.vimPlugins; [
        # Dependencies & utilities
        plenary-nvim
        nvim-web-devicons

        # Treesitter, pre-install all grammars
        nvim-treesitter.withAllGrammars

        # Theme
        tokyonight-nvim

        # Editor setup
        nvim-tree-lua
        gitsigns-nvim
        indent-blankline-nvim

        # Autocomplete
        nvim-cmp
        cmp-buffer

        # Telescope
        telescope-nvim
      ];
    };

    xdg.configFile.nvim = {
      source = ../static/nvim;
      recursive = true;
    };
  };
}
