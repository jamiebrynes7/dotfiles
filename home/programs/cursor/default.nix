{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.dotfiles.programs.cursor;
  aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "cursor";
    targetDir = ".cursor/skills";
    skillsDirs = cfg.skillsDirs;
  };

  mcpTypes = import ./mcp-types.nix { inherit lib; };
  mergedMcpServers = mcpTypes.mergeMcpServers cfg.mcpServers;
  hasMcpServers = mergedMcpServers != { };
  mcpJson = pkgs.writeText "mcp.json" (builtins.toJSON { mcpServers = mergedMcpServers; });
  mcpAssertions = mcpTypes.mkServerAssertions cfg.mcpServers;
in
{
  options.dotfiles.programs.cursor = {
    enable = mkEnableOption "Enable cursor";
    skillsDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "List of paths to skill directories to symlink into ~/.cursor/skills.";
    };
    mcpServers = mkOption {
      type = types.attrsOf mcpTypes.mcpServerType;
      default = { };
      description = "Named MCP server definitions for Cursor";
    };
  };

  config = mkIf cfg.enable {
    dotfiles.programs.cursor.skillsDirs = [ aiSkills.builtinSkillsDir ];

    assertions = [
      {
        assertion = skills.conflicts == [ ];
        message = "cursor: skill name conflicts between built-in skills and provided skills: ${builtins.concatStringsSep ", " skills.conflicts}";
      }
    ]
    ++ mcpAssertions;

    home.file = skills.files // (optionalAttrs hasMcpServers { ".cursor/mcp.json".source = mcpJson; });
  };
}
