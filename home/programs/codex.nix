{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.codex;
  aiSkills = import ../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "codex";
    targetDir = ".codex/skills";
    skillsDirs = cfg.skillsDirs;
    # Codex follows symlinked skill directories but ignores symlinked SKILL.md
    # files, so symlink the directory itself rather than recreating the tree.
    recursive = false;
  };
  codexConfig = (pkgs.formats.toml { }).generate "codex-dotfiles.toml" {
    features.hooks = cfg.hooks;
  };
  codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
    exec ${pkgs.dotfiles.codex}/bin/codex --profile dotfiles "$@"
  '';
in {
  options.dotfiles.programs.codex = {
    enable = mkEnableOption "Enable codex";
    skillsDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description =
        "List of paths to skill directories to symlink into ~/.codex/skills.";
    };
    hooks = mkOption {
      type = types.bool;
      default = true;
      description =
        "Enable Codex lifecycle hooks ([features].hooks) via the dotfiles profile overlay.";
    };
  };

  config = mkIf cfg.enable {
    dotfiles.programs.codex.skillsDirs = [ aiSkills.builtinSkillsDir ];
    dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ];

    assertions = [{
      assertion = skills.conflicts == [ ];
      message =
        "codex: skill name conflicts between built-in skills and provided skills: ${
          builtins.concatStringsSep ", " skills.conflicts
        }";
    }];

    # Shared global agent instructions (also deployed to ~/.claude/CLAUDE.md) and
    # the Nix-managed profile overlay codex always loads via --profile dotfiles.
    home.file = skills.files // {
      ".codex/AGENTS.md".source = ../lib/ai/global-instructions.md;
      ".codex/dotfiles.config.toml".source = codexConfig;
    };

    # Wrap codex so it always loads the dotfiles profile overlay. The wrapper
    # references the unbundled codex by store path (it shells out to an ambient
    # `rg`, provided by the base profile), so codex is realised without being a
    # bare entry on PATH.
    home.activation.codexStableLink =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        install -m755 ${codexWrapper} "$HOME/.local/bin/codex"
      '';
  };
}
