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
    dotfiles.programs.claude-code.permissions = { allow = [ "Skill" ]; };

    assertions = [{
      assertion = commands.conflicts == [ ];
      message =
        "claude-code: command name conflicts between built-in commands and provided commands: ${
          builtins.concatStringsSep ", " commands.conflicts
        }";
    }];

    home.file = {
      ".claude/CLAUDE.md".source = ./CLAUDE.md;
      ".claude/settings.json".source = settingsJson;
    } // commands.files;

    home.activation.claudeStableLink =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        install -m755 ${claudeWrapper} "$HOME/.local/bin/claude"
      '';

    # Add to PATH
    home.sessionPath = [ "$HOME/.local/bin" ];

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
