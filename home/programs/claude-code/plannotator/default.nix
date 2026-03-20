{ config, lib, pkgs, ... }:
let
  plannotator = pkgs.callPackage ../../../../packages/plannotator { };
  cfg = config.dotfiles.programs.claude-code.plannotator;

  plannotatorWrapper = pkgs.writeShellScriptBin "plannotator" ''
    ${lib.optionalString cfg.remote "export PLANNOTATOR_REMOTE=1"}
    ${lib.optionalString (cfg.port != null)
    "export PLANNOTATOR_PORT=${toString cfg.port}"}
    exec ${plannotator}/bin/plannotator "$@"
  '';
in {
  options.dotfiles.programs.claude-code.plannotator = {
    enable = lib.mkEnableOption "Enable plannotator";
    remote = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description =
        "Enable plannotator remote mode (sets PLANNOTATOR_REMOTE=1)";
    };
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Port for plannotator remote mode (sets PLANNOTATOR_PORT)";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ plannotatorWrapper ];

    dotfiles.programs.claude-code.hooks = {
      plannotator-review = {
        enable = true;
        event = "PermissionRequest";
        matcher = "ExitPlanMode";
        hooks = [{
          type = "command";
          command = "${plannotatorWrapper}/bin/plannotator";
          timeout = 345600;
        }];
      };
    };
  };
}
