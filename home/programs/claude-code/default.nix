{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.claude-code;
  aiCommands = import ../../lib/ai/commands { inherit lib pkgs; };
  commands = aiCommands.mkCommandFiles {
    variant = "cc";
    targetDir = ".claude/commands";
    extraCommandsDir = cfg.commandsDir;
  };
  aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "cc";
    targetDir = ".claude/skills";
    extraSkillsDir = cfg.skillsDir;
  };

  claudeWrapper = pkgs.writeShellScript "claude-wrapper" ''
    ${cfg.extraScript}
    exec ${pkgs.claude-code}/bin/claude "$@"
  '';

  hookTypes = import ./hooks/types.nix { inherit lib; };
  mergedHooks = hookTypes.mergeHooks cfg.hooks;

  settingsJson = pkgs.writeText "claude-settings.json" (builtins.toJSON {
    alwaysThinkingEnabled = true;
    hooks = mergedHooks;
    permissions = cfg.permissions;
  });
in {
  imports = [ ./hooks ];

  options.dotfiles.programs.claude-code = {
    enable = mkEnableOption "Enable claude-code";
    extraScript = mkOption {
      type = types.lines;
      default = "";
      description =
        "Shell lines to run before execing claude-code (e.g. env tweaks).";
    };
    commandsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description =
        "Path to a directory of additional command files to symlink into ~/.claude/commands.";
    };
    skillsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description =
        "Path to a directory of additional skill directories to symlink into ~/.claude/skills.";
    };
    hooks = mkOption {
      type = types.attrsOf hookTypes.hookType;
      default = { };
      description = "Named hook definitions for Claude Code";
    };
    permissions = mkOption {
      type = types.submodule {
        options = {
          allow = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of permissions to allow.";
          };
          deny = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of permissions to deny.";
          };
        };
      };
      default = {
        allow = [ ];
        deny = [ ];
      };
      description = "Permissions configuration for Claude Code.";
    };
  };

  config = mkIf cfg.enable {
    dotfiles.programs.claude-code.permissions = {
      allow = [
        "Skill"
        "Read(//tmp/claude-pr-review/**)"
        "Grep(//tmp/claude-pr-review/**)"
        "Glob(//tmp/claude-pr-review/**)"
      ];
    };

    assertions = [
      {
        assertion = commands.conflicts == [ ];
        message =
          "claude-code: command name conflicts between built-in commands and provided commands: ${
            builtins.concatStringsSep ", " commands.conflicts
          }";
      }
      {
        assertion = skills.conflicts == [ ];
        message =
          "claude-code: skill name conflicts between built-in skills and provided skills: ${
            builtins.concatStringsSep ", " skills.conflicts
          }";
      }
    ];

    home.file = {
      ".claude/CLAUDE.md".source = ./CLAUDE.md;
      ".claude/settings.json".source = settingsJson;
    } // commands.files // skills.files;

    home.activation.claudeStableLink =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        install -m755 ${claudeWrapper} "$HOME/.local/bin/claude"
      '';

    # Add to PATH
    programs.zsh.envExtra = ''
      export PATH="$HOME/.local/bin:$PATH"
    '';

    # Preserve config during switches
    home.activation.preserveClaudeConfig =
      lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
      '';

    home.activation.restoreClaudeConfig =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
      '';
  };
}
