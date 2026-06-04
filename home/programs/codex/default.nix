{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.codex;
  aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "codex";
    targetDir = ".codex/skills";
    skillsDirs = cfg.skillsDirs;
    # Codex follows symlinked skill directories but ignores symlinked SKILL.md
    # files, so symlink the directory itself rather than recreating the tree.
    recursive = false;
  };
  hookTypes = import ./hooks/types.nix { inherit lib; };
  mergedHooks = hookTypes.mergeHooks cfg.hooks;
  codexConfig = (pkgs.formats.toml { }).generate "codex-dotfiles.toml" {
    features.hooks = cfg.enableHooks;
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
    enableHooks = mkOption {
      type = types.bool;
      default = true;
      description =
        "Enable Codex lifecycle hooks ([features].hooks) via the dotfiles profile overlay.";
    };
    hooks = mkOption {
      type = types.attrsOf hookTypes.hookType;
      default = { };
      description =
        "Named Codex hook definitions rendered to ~/.codex/hooks.json.";
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

    warnings = lib.optional (cfg.hooks != { } && !cfg.enableHooks)
      "codex: hooks are declared but dotfiles.programs.codex.enableHooks is false; they will never fire.";

    # Shared global agent instructions (also deployed to ~/.claude/CLAUDE.md) and
    # the Nix-managed profile overlay codex always loads via --profile dotfiles.
    home.file = skills.files // {
      ".codex/AGENTS.md".source = ../../lib/ai/global-instructions.md;
      ".codex/dotfiles.config.toml".source = codexConfig;
    } // lib.optionalAttrs (mergedHooks != { }) {
      ".codex/hooks.json".source = pkgs.writeText "codex-hooks.json"
        (builtins.toJSON { hooks = mergedHooks; });
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
