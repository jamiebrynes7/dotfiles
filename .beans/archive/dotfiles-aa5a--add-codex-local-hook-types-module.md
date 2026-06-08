---
# dotfiles-aa5a
title: Add codex-local hook types module
status: completed
type: task
priority: normal
created_at: 2026-06-04T12:57:21Z
updated_at: 2026-06-04T13:07:07Z
parent: dotfiles-5gsf
blocked_by:
    - dotfiles-rzxu
---

Add codex's own hook submodule types and the `mergeHooks` transform. Modeled on `home/programs/claude-code/hooks/types.nix` but with codex's event enum and an extra codex-native optional `statusMessage` command field. This file is created but not yet consumed (next task wires it) — the flake still builds.

**Files:**
- Create: `home/programs/codex/hooks/types.nix`

- [x] **Step 1: Create the types module**

`home/programs/codex/hooks/types.nix`:

```nix
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
  mergeHooks = hookDefs:
    let
      enabledHooks = filterAttrs (_: h: h.enable) hookDefs;

      mkHookCommand = cmd:
        { type = cmd.type; command = cmd.command; }
        // (optionalAttrs (cmd.timeout != null) { timeout = cmd.timeout; })
        // (optionalAttrs (cmd.statusMessage != null) {
          statusMessage = cmd.statusMessage;
        });

      mkHookEntry = _name: hook: {
        inherit (hook) event;
        entry =
          (optionalAttrs (hook.matcher != null) { matcher = hook.matcher; })
          // { hooks = map mkHookCommand hook.hooks; };
      };

      hookEntries = mapAttrsToList mkHookEntry enabledHooks;
      groupedByEvent = groupBy (e: e.event) hookEntries;
    in mapAttrs (_event: entries: map (e: e.entry) entries) groupedByEvent;

in { inherit hookEvents hookCommandType hookType mergeHooks; }
```

- [x] **Step 2: Format**

Run: `nixfmt home/programs/codex/hooks/types.nix`

- [x] **Step 3: Validate the flake still evaluates**

Run: `nix flake check`
Expected: PASS (new file is not yet imported by anything, so this only confirms it parses/formats).

- [x] **Step 4: Commit**

```bash
git add home/programs/codex/hooks/types.nix
git commit -m "home/programs/codex: add local hook types module

Bean: <this-task-id>"
```

## Summary of Changes

Added home/programs/codex/hooks/types.nix defining codex-local hook submodule types (hookCommandType with an extra codex-native optional statusMessage field, hookType), the codex hookEvents enum, and a mergeHooks transform that groups enabled named hooks by event into the Codex hooks.json shape (dropping null timeout/statusMessage/matcher). Not yet consumed; nix flake check passes. Plannotator user review: no changes requested.
