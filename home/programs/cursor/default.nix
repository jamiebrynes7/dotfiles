{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.cursor;
  aiCommands = import ../../lib/ai/commands { inherit lib pkgs; };
  commands = aiCommands.mkCommandFiles {
    variant = "cursor";
    targetDir = ".cursor/commands";
    extraCommandsDir = cfg.commandsDir;
  };
  aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "cursor";
    targetDir = ".cursor/skills";
    extraSkillsDir = cfg.skillsDir;
  };

  mcpTypes = import ./mcp-types.nix { inherit lib; };
  mergedMcpServers = mcpTypes.mergeMcpServers cfg.mcpServers;
  hasMcpServers = mergedMcpServers != { };
  mcpJson = pkgs.writeText "mcp.json" (builtins.toJSON {
    mcpServers = mergedMcpServers;
  });

  # Validation: each enabled server must set exactly one of command or url.
  mcpAssertions =
    let
      enabledServers = filterAttrs (_: s: s.enable) cfg.mcpServers;
    in
    mapAttrsToList (name: server: {
      assertion = (server.command != null) != (server.url != null);
      message =
        "cursor: MCP server '${name}' must set exactly one of 'command' (stdio) or 'url' (remote), not both or neither.";
    }) enabledServers;
in {
  options.dotfiles.programs.cursor = {
    enable = mkEnableOption "Enable cursor";
    commandsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description =
        "Path to a directory of additional command files to symlink into ~/.cursor/commands.";
    };
    skillsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description =
        "Path to a directory of additional skill directories to symlink into ~/.cursor/skills.";
    };
    mcpServers = mkOption {
      type = types.attrsOf mcpTypes.mcpServerType;
      default = { };
      description = "Named MCP server definitions for Cursor";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = commands.conflicts == [ ];
        message =
          "cursor: command name conflicts between built-in commands and provided commands: ${
            builtins.concatStringsSep ", " commands.conflicts
          }";
      }
      {
        assertion = skills.conflicts == [ ];
        message =
          "cursor: skill name conflicts between built-in skills and provided skills: ${
            builtins.concatStringsSep ", " skills.conflicts
          }";
      }
    ] ++ mcpAssertions;

    home.file = commands.files // skills.files
      // (optionalAttrs hasMcpServers {
        ".cursor/mcp.json".source = mcpJson;
      });
  };
}
