{ lib }:
with lib;
let
  hookEvents = [
    "SessionStart"
    "UserPromptSubmit"
    "PreToolUse"
    "PermissionRequest"
    "PostToolUse"
    "PreCompact"
    "PostCompact"
    "SubagentStart"
    "SubagentStop"
    "Stop"
  ];

  hookCommandType = types.submodule {
    options = {
      type = mkOption {
        type = types.enum [ "command" ];
        default = "command";
        description = "The type of hook (currently only 'command' is supported)";
      };
      command = mkOption {
        type = types.str;
        description = "The command to execute";
      };
      timeout = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Timeout in seconds for the command";
      };
      statusMessage = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional status text shown in the Codex UI while the hook runs";
      };
    };
  };

  hookType = types.submodule {
    options = {
      enable = mkEnableOption "this hook";
      event = mkOption {
        type = types.enum hookEvents;
        description = "The hook event to attach to";
      };
      matcher = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Tool pattern matcher (for tool-related events)";
      };
      hooks = mkOption {
        type = types.listOf hookCommandType;
        description = "List of hook commands to execute";
      };
    };
  };

  # Merge named hook definitions into Codex's hooks.json structure.
  # Input:  attrset of named hooks ({ name = { enable, event, matcher, hooks }; })
  # Output: attrset grouped by event ({ Stop = [ { matcher?, hooks } ]; })
  mergeHooks =
    hookDefs:
    let
      enabledHooks = filterAttrs (_: h: h.enable) hookDefs;

      mkHookCommand =
        cmd:
        {
          type = cmd.type;
          command = cmd.command;
        }
        // (optionalAttrs (cmd.timeout != null) { timeout = cmd.timeout; })
        // (optionalAttrs (cmd.statusMessage != null) {
          statusMessage = cmd.statusMessage;
        });

      mkHookEntry = _name: hook: {
        inherit (hook) event;
        entry = (optionalAttrs (hook.matcher != null) { matcher = hook.matcher; }) // {
          hooks = map mkHookCommand hook.hooks;
        };
      };

      hookEntries = mapAttrsToList mkHookEntry enabledHooks;
      groupedByEvent = groupBy (e: e.event) hookEntries;
    in
    mapAttrs (_event: entries: map (e: e.entry) entries) groupedByEvent;

in
{
  inherit
    hookEvents
    hookCommandType
    hookType
    mergeHooks
    ;
}
