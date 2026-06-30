{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.dotfiles.programs.claude-code;
  aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "cc";
    targetDir = ".claude/skills";
    skillsDirs = cfg.skillsDirs;
  };

  claudeWrapper = pkgs.writeShellScript "claude-wrapper" ''
    ${cfg.extraScript}
    export BASH_MAX_TIMEOUT_MS=1800000
    exec ${pkgs.claude-code}/bin/claude "$@"
  '';

  hookTypes = import ./hooks/types.nix { inherit lib; };
  mergedHooks = hookTypes.mergeHooks cfg.hooks;

  settingsJson = pkgs.writeText "claude-settings.json" (
    builtins.toJSON (
      {
        alwaysThinkingEnabled = true;
        autoMemoryEnabled = false;
        hooks = mergedHooks;
        permissions = {
          inherit (cfg.permissions) allow deny;
        }
        // lib.optionalAttrs (cfg.permissions.defaultMode != null) {
          inherit (cfg.permissions) defaultMode;
        };
      }
      // lib.optionalAttrs (cfg.statusLine != null) {
        statusLine = cfg.statusLine;
      }
      // lib.optionalAttrs (cfg.skillOverrides != { }) {
        skillOverrides = cfg.skillOverrides;
      }
    )
  );
in
{
  imports = [
    ./hooks
    ./cship
  ];

  options.dotfiles.programs.claude-code = {
    enable = mkEnableOption "Enable claude-code";
    extraScript = mkOption {
      type = types.lines;
      default = "";
      description = "Shell lines to run before execing claude-code (e.g. env tweaks).";
    };
    skillsDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "List of paths to skill directories to symlink into ~/.claude/skills.";
    };
    hooks = mkOption {
      type = types.attrsOf hookTypes.hookType;
      default = { };
      description = "Named hook definitions for Claude Code";
    };
    statusLine = mkOption {
      type = types.nullOr (types.attrsOf types.str);
      default = null;
      description = "Status line configuration for Claude Code.";
    };
    permissions = mkOption {
      type = types.submodule {
        options = {
          allow = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of permissions to allow.";
          };
          deny = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of permissions to deny.";
          };
          defaultMode = mkOption {
            type = types.nullOr (
              types.enum [
                "default"
                "acceptEdits"
                "plan"
                "auto"
                "dontAsk"
                "bypassPermissions"
              ]
            );
            default = "auto";
            description = ''
              Default permission mode written to settings.json as
              permissions.defaultMode. Defaults to "auto". Set to null to
              omit the key entirely. See
              https://code.claude.com/docs/en/permission-modes#switch-permission-modes.
            '';
          };
        };
      };
      default = {
        allow = [ ];
        deny = [ ];
      };
      description = "Permissions configuration for Claude Code.";
    };
    skillOverrides = mkOption {
      type = types.attrsOf (
        types.enum [
          "on"
          "name-only"
          "user-invocable-only"
          "off"
        ]
      );
      default = { };
      description = ''
        Per-skill visibility overrides written to settings.json.
        Keys are skill names; values are one of "on", "name-only",
        "user-invocable-only", or "off". See
        https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings.
      '';
    };
  };

  config = mkIf cfg.enable {
    dotfiles.programs.claude-code.skillsDirs = [ aiSkills.builtinSkillsDir ];

    dotfiles.programs.claude-code.permissions = {
      allow = [
        "Skill"

        # PR review skill
        "Read(//tmp/claude-pr-review/**)"
        "Grep(//tmp/claude-pr-review/**)"
        "Glob(//tmp/claude-pr-review/**)"

        # Git read-only
        "Bash(git log *)"
        "Bash(git diff *)"
        "Bash(git status *)"
        "Bash(git show *)"
        "Bash(git rev-parse *)"

        # Common read-only shell commands
        "Bash(find *)"
        "Bash(grep *)"
        "Bash(head *)"
        "Bash(ls *)"
        "Bash(tail *)"
        "Bash(wc *)"
        "Bash(which *)"
        "Bash(cat *)"
        "Bash(diff *)"

        # Text processing
        "Bash(jq *)"
        "Bash(sort *)"
        "Bash(uniq *)"
      ];
      deny = [ "Read(**/.env.local)" ];
    };

    dotfiles.programs.claude-code.skillOverrides = {
      claude-api = "off";
      fewer-permission-prompts = "off";
      init = "off";
      keybindings-help = "off";
      loop = "off";
      review = "off";
      schedule = "off";
      security-review = "off";
      update-config = "off";
    };

    assertions = [
      {
        assertion = skills.conflicts == [ ];
        message = "claude-code: skill name conflicts between built-in skills and provided skills: ${builtins.concatStringsSep ", " skills.conflicts}";
      }
    ];

    home.file = {
      ".claude/CLAUDE.md".source = ../../lib/ai/global-instructions.md;
      ".claude/settings.json".source = settingsJson;
    }
    // skills.files;

    programs.git.ignores = [ "**/.claude/settings.local.json" ];

    home.activation.claudeStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.local/bin
      install -m755 ${claudeWrapper} "$HOME/.local/bin/claude"
    '';

    dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ];

    # Preserve config during switches
    home.activation.preserveClaudeConfig = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
    '';

    home.activation.restoreClaudeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
    '';
  };
}
