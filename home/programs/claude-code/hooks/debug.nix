{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.claude-code;
  hookTypes = import ./types.nix { inherit lib; };

  script = pkgs.writeShellScript "claude-debug-hook" ''
    set -euo pipefail

    # Exit early if debug not enabled
    [ -z "''${CLAUDE_DEBUG_HOOKS:-}" ] && exit 0

    # Read stdin payload
    PAYLOAD=$(cat)

    # Extract session_id from payload
    SESSION_ID=$(echo "$PAYLOAD" | ${pkgs.jq}/bin/jq -r '.session_id // "unknown"')

    # Write to well-known directory, keyed by session
    LOG_DIR="/tmp/claude-hooks-debug"
    mkdir -p "$LOG_DIR"

    LOG_FILE="$LOG_DIR/$SESSION_ID.log"

    # Append to log
    {
      echo "---"
      echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "payload: $PAYLOAD"
    } >> "$LOG_FILE"
  '';

  # Generate one hook definition per event type
  debugHooks = builtins.listToAttrs (map (event: {
    name = "debug-${event}";
    value = mkIf cfg.enable {
      enable = true;
      inherit event;
      hooks = [{
        type = "command";
        command = "${script}";
      }];
    };
  }) hookTypes.hookEvents);
in { config.dotfiles.programs.claude-code.hooks = debugHooks; }
