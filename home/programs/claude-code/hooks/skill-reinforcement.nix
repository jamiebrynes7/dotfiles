{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.claude-code;

  script = pkgs.writeShellScript "skill-reinforcement-hook" ''
    set -euo pipefail

    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<EXTREMELY_IMPORTANT>\nBefore responding to this prompt, consider whether you have any skills in <available_skills /> that apply. If you do and they have not been activated in this session, use the Skill tool to activate them.\n</EXTREMELY_IMPORTANT>"
  }
}
EOF
  '';
in {
  config.dotfiles.programs.claude-code.hooks.skill-reinforcement = mkIf cfg.enable {
    enable = true;
    event = "UserPromptSubmit";
    hooks = [{
      type = "command";
      command = "${script}";
    }];
  };
}
