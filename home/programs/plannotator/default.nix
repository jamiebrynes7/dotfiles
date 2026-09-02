{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.programs.plannotator;

  portEnv =
    if cfg.portRange != null then
      "${toString cfg.portRange.from}-${toString cfg.portRange.to}"
    else if cfg.port != null then
      toString cfg.port
    else
      null;

  plannotatorWrapper = pkgs.writeShellScriptBin "plannotator" ''
    ${lib.optionalString cfg.remote "export PLANNOTATOR_REMOTE=1"}
    ${lib.optionalString (portEnv != null) "export PLANNOTATOR_PORT=${portEnv}"}
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
      description = ''
        Fixed port for plannotator remote mode (sets PLANNOTATOR_PORT). Mutually
        exclusive with `portRange`.
      '';
    };
    portRange = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            from = lib.mkOption {
              type = lib.types.port;
              description = "First port in the range (inclusive).";
            };
            to = lib.mkOption {
              type = lib.types.port;
              description = "Last port in the range (inclusive).";
            };
          };
        }
      );
      default = null;
      example = {
        from = 61001;
        to = 61005;
      };
      description = ''
        Inclusive port range for plannotator remote mode (sets PLANNOTATOR_PORT
        to `from-to`). Plannotator takes the first free port in the range
        immediately; a fixed `port` instead retries that one port and then
        fails. Mutually exclusive with `port`.
      '';
    };
    claude-code.enable = lib.mkEnableOption "plannotator for claude-code";
    codex.enable = lib.mkEnableOption "plannotator for codex";
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.port == null || cfg.portRange == null;
          message = "dotfiles.programs.plannotator.port and .portRange are mutually exclusive -- both set PLANNOTATOR_PORT.";
        }
        {
          # Plannotator answers a malformed range by warning on stderr and
          # falling back to its default 19432, so a bad range here surfaces as
          # "the review opened on a port nothing routes to" rather than as an
          # error.
          assertion =
            cfg.portRange == null || (cfg.portRange.from >= 1 && cfg.portRange.from <= cfg.portRange.to);
          message = "dotfiles.programs.plannotator.portRange needs 1 <= from <= to.";
        }
      ];
    }
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
