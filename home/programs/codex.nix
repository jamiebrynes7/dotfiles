{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.codex;
  aiSkills = import ../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "codex";
    targetDir = ".codex/skills";
    skillsDirs = cfg.skillsDirs;
  };
in {
  options.dotfiles.programs.codex = {
    enable = mkEnableOption "Enable codex";
    skillsDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description =
        "List of paths to skill directories to symlink into ~/.codex/skills.";
    };
  };

  config = mkIf cfg.enable {
    dotfiles.programs.codex.skillsDirs = [ aiSkills.builtinSkillsDir ];

    assertions = [{
      assertion = skills.conflicts == [ ];
      message =
        "codex: skill name conflicts between built-in skills and provided skills: ${
          builtins.concatStringsSep ", " skills.conflicts
        }";
    }];

    # The codex binary is unbundled: it shells out to an ambient `rg` and, on
    # Linux only, `bubblewrap` for sandboxing. Neither is added here — codex
    # relies on those being on PATH (the base profile already provides ripgrep).
    home.packages = [ pkgs.dotfiles.codex ];

    # Shared global agent instructions (also deployed to ~/.claude/CLAUDE.md).
    home.file = skills.files // {
      ".codex/AGENTS.md".source = ../lib/ai/global-instructions.md;
    };
  };
}
