{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.dotfiles.programs.codex;
  aiSkills = import ../../lib/ai/skills { inherit lib pkgs; };
  skills = aiSkills.mkSkillFiles {
    variant = "codex";
    targetDir = ".codex/skills";
    skillsDirs = cfg.skillsDirs;
    # Codex follows symlinked skill directories but ignores symlinked SKILL.md
    # files, so symlink the directory itself rather than recreating the tree.
    recursive = false;
  };
  hookTypes = import ./hooks/types.nix { inherit lib; };
  mergedHooks = hookTypes.mergeHooks cfg.hooks;
  # Managed Codex settings, injected as session-only `-c key=value` overrides
  # (precedence 30). Codex never persists `-c` flags, so there is no managed file
  # for it to clobber. Dotted keys map straight to Codex config paths; bool values
  # render as bare TOML `true`/`false`; string values embed their own TOML quotes
  # (e.g. `''"auto_review"''`).
  managedConfig = {
    "features.hooks" = lib.boolToString cfg.enableHooks;
    "approvals_reviewer" = ''"${cfg.approvalsReviewer}"'';
  };
  configArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (k: v: "-c ${lib.escapeShellArg "${k}=${v}"}") managedConfig
  );
  codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
    exec ${pkgs.dotfiles.codex}/bin/codex ${configArgs} "$@"
  '';
in
{
  options.dotfiles.programs.codex = {
    enable = mkEnableOption "Enable codex";
    skillsDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "List of paths to skill directories to symlink into ~/.codex/skills.";
    };
    enableHooks = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Codex lifecycle hooks ([features].hooks), injected as a -c session flag by the codex wrapper.";
    };
    approvalsReviewer = mkOption {
      type = types.str;
      default = "auto_review";
      description = "Value for Codex's approvals_reviewer setting, injected as a -c session flag by the codex wrapper.";
    };
    hooks = mkOption {
      type = types.attrsOf hookTypes.hookType;
      default = { };
      description = "Named Codex hook definitions rendered to ~/.codex/hooks.json.";
    };
  };

  config = mkIf cfg.enable {
    dotfiles.programs.codex.skillsDirs = [ aiSkills.builtinSkillsDir ];
    dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ];

    # On Linux, Codex sandboxes commands with bubblewrap (`bwrap`), expecting it
    # on PATH. macOS uses Seatbelt instead, so it is only needed here.
    home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.bubblewrap ];

    assertions = [
      {
        assertion = skills.conflicts == [ ];
        message = "codex: skill name conflicts between built-in skills and provided skills: ${builtins.concatStringsSep ", " skills.conflicts}";
      }
    ];

    warnings =
      lib.optional (cfg.hooks != { } && !cfg.enableHooks)
        "codex: hooks are declared but dotfiles.programs.codex.enableHooks is false; they will never fire.";

    # Shared global agent instructions (also deployed to ~/.claude/CLAUDE.md).
    # Managed settings are injected at runtime via the wrapper's `-c` flags, not a
    # config file, so there is nothing here for codex to clobber.
    home.file =
      skills.files
      // {
        ".codex/AGENTS.md".source = ../../lib/ai/global-instructions.md;
      }
      // lib.optionalAttrs (mergedHooks != { }) {
        ".codex/hooks.json".source = pkgs.writeText "codex-hooks.json" (
          builtins.toJSON { hooks = mergedHooks; }
        );
      };

    # Wrap codex so it always runs with the managed `-c` overrides injected. The
    # wrapper references the unbundled codex by store path (it shells out to an
    # ambient `rg`, provided by the base profile), so codex is realised without
    # being a bare entry on PATH.
    home.activation.codexStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.local/bin
      install -m755 ${codexWrapper} "$HOME/.local/bin/codex"
    '';
  };
}
