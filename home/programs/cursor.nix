{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.cursor;
  aiCommands = import ../lib/ai/commands { inherit lib pkgs; };
  commands = aiCommands.mkCommandFiles {
    variant = "cursor";
    targetDir = ".cursor/commands";
    extraCommandsDir = cfg.commandsDir;
  };
in {
  options.dotfiles.programs.cursor = {
    enable = mkEnableOption "Enable cursor";
    commandsDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description =
        "Path to a directory of additional command files to symlink into ~/.cursor/commands.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = commands.conflicts == [ ];
      message =
        "cursor: command name conflicts between built-in commands and provided commands: ${
          builtins.concatStringsSep ", " commands.conflicts
        }";
    }];

    home.file = commands.files;
  };
}
