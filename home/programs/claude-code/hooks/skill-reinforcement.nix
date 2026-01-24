{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.dotfiles.programs.claude-code;

  script = pkgs.writeShellScript "skill-reinforcement-hook" ''
    set -euo pipefail

    cat <<'EOF'
      INSTRUCTION: MANDATORY SKILL ACTIVATION SEQUENCE

      Step 1 - EVALUATE (do this in your response):
      For each skill in <available_skills>, state: [skill-name] - YES/NO - [reason]

      Step 2 - ACTIVATE (do this immediately after Step 1):
      IF any skills are YES → Use Skill(skill-name) tool for EACH relevant skill NOW
      IF no skills are YES → State "No skills needed" and proceed

      Step 3 - IMPLEMENT:
      Only after Step 2 is complete, proceed with implementation.

      CRITICAL: You MUST call Skill() tool in Step 2. Do NOT skip to implementation.
      The evaluation (Step 1) is WORTHLESS unless you ACTIVATE (Step 2) the skills.

      Example of correct sequence:
      - research: NO - not a research task
      - write-git-commit: YES - changes to codebase need committing

      [Then IMMEDIATELY use Skill() tool:]
      > Skill(write-git-commit)

      [THEN and ONLY THEN continue]

      END OF INSTRUCTION
    EOF
  '';
in {
  config.dotfiles.programs.claude-code.hooks.skill-reinforcement =
    mkIf cfg.enable {
      enable = true;
      event = "UserPromptSubmit";
      hooks = [{
        type = "command";
        command = "${script}";
      }];
    };
}
