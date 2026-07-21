{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.programs.plannotator;

  plannotatorWrapper = pkgs.writeShellScriptBin "plannotator" ''
    ${lib.optionalString cfg.remote "export PLANNOTATOR_REMOTE=1"}
    ${lib.optionalString (cfg.port != null) "export PLANNOTATOR_PORT=${toString cfg.port}"}
    exec ${pkgs.dotfiles.plannotator}/bin/plannotator "$@"
  '';

  # Plannotator is one tool; only the plan-review hook event differs per
  # assistant (claude-code fires on the ExitPlanMode permission prompt; codex
  # fires on Stop). The command references the wrapper by store path so neither
  # assistant depends on the other being enabled.
  plannotatorHook = event: matcher: {
    enable = true;
    inherit event matcher;
    hooks = [
      {
        type = "command";
        command = "${plannotatorWrapper}/bin/plannotator";
        timeout = 345600;
      }
    ];
  };

  # Code-review "denied" feedback: keep triage + concreteness, drop the
  # "independently review the diff yourself" instruction from the default.
  reviewDeniedPrompt = ''
    The findings above are reviewer comments on the current changes.

    Triage each incoming finding — open the code it points at and give a verdict (Confirmed / Partly / Not a bug / Intended) with evidence (file:line + what the code actually does). Say whether it's introduced by these changes, pre-existing, or a deliberate scope decision. Rank by real user impact.

    For each confirmed issue, describe it concretely: the exact place it lives and the real-world trigger that hits it — the specific call, endpoint, command, input, or user action — plus the conditions under which it goes wrong. Not an abstract description.'';

  configJson = pkgs.writeText "plannotator-config.json" (
    builtins.toJSON {
      diffOptions.defaultDiffType = "uncommitted";
      prompts.review.denied = reviewDeniedPrompt;
    }
  );
in
{
  options.dotfiles.programs.plannotator = {
    remote = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable plannotator remote mode (sets PLANNOTATOR_REMOTE=1)";
    };
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Port for plannotator remote mode (sets PLANNOTATOR_PORT)";
    };
    claude-code.enable = lib.mkEnableOption "plannotator for claude-code";
    codex.enable = lib.mkEnableOption "plannotator for codex";
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.claude-code.enable || cfg.codex.enable) {
      home.packages = [ plannotatorWrapper ];
      home.file.".plannotator/config.json".source = configJson;
    })
    (lib.mkIf cfg.claude-code.enable {
      dotfiles.programs.claude-code.skillsDirs = [ ./skills ];
      dotfiles.programs.claude-code.hooks.plannotator-review =
        plannotatorHook "PermissionRequest" "ExitPlanMode";
    })
    (lib.mkIf cfg.codex.enable {
      dotfiles.programs.codex.skillsDirs = [ ./skills ];
      dotfiles.programs.codex.hooks.plannotator-review = plannotatorHook "Stop" null;
    })
  ];
}
