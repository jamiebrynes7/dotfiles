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
  # The one definition of "can bwrap create a user namespace here?", shared by the codex
  # wrapper, the activation warning, and codex-apparmor-setup. The installer must not
  # re-implement the check it exists to satisfy, or it could report success while the
  # wrapper still refuses to start. Tests the capability directly rather than inferring it
  # from sysctls or profile paths, both of which are distro-specific: NixOS loads profiles
  # from the store via security.apparmor.policies and never populates /etc/apparmor.d.
  # Does not silence bwrap — callers wanting quiet redirect, and codex-apparmor-setup wants
  # the real error when its final re-probe fails.
  bwrapUsernsProbe = pkgs.writeShellScript "codex-bwrap-userns-probe" ''
    exec ${pkgs.bubblewrap}/bin/bwrap --unshare-user --ro-bind / / ${pkgs.coreutils}/bin/true
  '';
  # Empty unless bwrap is actually the active backend: with useLegacyLandlock on, codex
  # never invokes bwrap, so probing it would be misleading noise. `onFailure` is the only
  # thing that differs between the wrapper (which bails) and activation (which warns).
  mkBwrapUsernsCheck =
    onFailure:
    lib.optionalString (pkgs.stdenv.isLinux && !cfg.useLegacyLandlock) ''
      if [ -z "''${DOTFILES_CODEX_SKIP_SANDBOX_CHECK:-}" ] && ! ${bwrapUsernsProbe} 2>/dev/null; then
        echo "codex: bwrap cannot create a user namespace on this host, so every sandboxed operation will fail." >&2
        echo "codex: usually AppArmor's userns restriction (Ubuntu 23.10+) — run 'codex-apparmor-setup', which diagnoses and fixes that case." >&2
        echo "codex: or set dotfiles.programs.codex.useLegacyLandlock = true to use the Landlock backend instead." >&2
        echo "codex: set DOTFILES_CODEX_SKIP_SANDBOX_CHECK to any non-empty value to bypass this check." >&2
        ${onFailure}
      fi
    '';
  bwrapCheckFatal = mkBwrapUsernsCheck "exit 1";
  bwrapCheckWarn = mkBwrapUsernsCheck "";
  apparmorSetup = pkgs.writeShellApplication {
    name = "codex-apparmor-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
    ];
    text =
      builtins.replaceStrings
        [ "@profile@" "@probe@" ]
        [ "${./nix-bwrap.apparmor}" "${bwrapUsernsProbe}" ]
        (builtins.readFile ./apparmor-setup.sh);
  };
  # Managed Codex settings, injected as session-only `-c key=value` overrides
  # (precedence 30). Codex never persists `-c` flags, so there is no managed file
  # for it to clobber. Dotted keys map straight to Codex config paths; bool values
  # render as bare TOML `true`/`false`; string values embed their own TOML quotes
  # (e.g. `''"auto_review"''`).
  managedConfig = {
    "features.hooks" = lib.boolToString cfg.enableHooks;
    "approvals_reviewer" = ''"${cfg.approvalsReviewer}"'';
  }
  // lib.optionalAttrs (pkgs.stdenv.isLinux && cfg.useLegacyLandlock) {
    "features.use_legacy_landlock" = "true";
  };
  configArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (k: v: "-c ${lib.escapeShellArg "${k}=${v}"}") managedConfig
  );
  codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
    ${bwrapCheckFatal}
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
    useLegacyLandlock = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Use Codex's legacy Landlock sandbox backend instead of bubblewrap. Linux only;
        ignored on darwin, which uses Seatbelt. Enable this on hosts with
        kernel.apparmor_restrict_unprivileged_userns = 1 (Ubuntu 23.10+), where bwrap from
        the Nix store matches no AppArmor profile and is denied the user namespace it needs.
        The alternative on such a host is to run codex-apparmor-setup, which installs a
        profile granting userns to /nix/store/*/bin/bwrap.
      '';
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

    # On Linux, Codex sandboxes commands with bubblewrap (`bwrap`), expecting it on PATH;
    # macOS uses Seatbelt instead. bwrap is the default backend — useLegacyLandlock switches
    # Codex off it — but it cannot work on hosts with
    # kernel.apparmor_restrict_unprivileged_userns = 1 until codex-apparmor-setup installs a
    # profile for it. The wrapper probes for exactly that and refuses to start.
    home.packages = lib.optionals pkgs.stdenv.isLinux [
      pkgs.bubblewrap
      apparmorSetup
    ];

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
    home.activation = {
      codexStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        install -m755 ${codexWrapper} "$HOME/.local/bin/codex"
      '';
    }
    # Warns rather than aborting: a fatal check here would brick `home-manager switch` on the
    # very host that needs fixing. The wrapper is the load-bearing site anyway, since it stays
    # correct on a host that has not rebuilt.
    // lib.optionalAttrs (bwrapCheckWarn != "") {
      codexSandboxCheck = lib.hm.dag.entryAfter [ "codexStableLink" ] bwrapCheckWarn;
    };
  };
}
