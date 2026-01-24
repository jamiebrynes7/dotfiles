{ lib }:
with lib;
let
  hookEvents = [
    "SessionStart"
    "UserPromptSubmit"
    "PreToolUse"
    "PermissionRequest"
    "PostToolUse"
    "PostToolUseFailure"
    "SubagentStart"
    "SubagentStop"
    "Stop"
    "PreCompact"
    "SessionEnd"
    "Notification"
    "Setup"
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

  # Merge hooks from multiple named hook definitions into the Claude settings format.
  # Input: attrset of named hooks (e.g., { skill-reinforcement = { enable, event, matcher, hooks }; })
  # Output: attrset grouped by event (e.g., { UserPromptSubmit = [ { matcher, hooks } ]; })
  mergeHooks = hookDefs:
    let
      enabledHooks = filterAttrs (_: h: h.enable) hookDefs;

      # Convert a hook command to JSON-compatible attrset
      mkHookCommand = cmd:
        { type = cmd.type; command = cmd.command; }
        // (optionalAttrs (cmd.timeout != null) { timeout = cmd.timeout; });

      # Convert a named hook to its entry format
      mkHookEntry = _name: hook: {
        inherit (hook) event;
        entry =
          (optionalAttrs (hook.matcher != null) { matcher = hook.matcher; })
          // { hooks = map mkHookCommand hook.hooks; };
      };

      # Group hooks by event
      hookEntries = mapAttrsToList mkHookEntry enabledHooks;
      groupedByEvent = groupBy (e: e.event) hookEntries;
    in
    mapAttrs (_event: entries: map (e: e.entry) entries) groupedByEvent;

in {
  inherit hookEvents hookCommandType hookType mergeHooks;
}
