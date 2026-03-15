{ config, pkgs, ... }:
let plannotator = pkgs.callPackage ../../../../packages/plannotator { };
in {
  config = {
    dotfiles.programs.claude-code.hooks = {
      plannotator-review = {
        enable = true;
        event = "PermissionRequest";
        matcher = "ExitPlanMode";
        hooks = [{
          type = "command";
          command = "${plannotator}/bin/plannotator";
          timeout = 345600;
        }];
      };
    };
  };
}
