---
# dotfiles-d6t2
title: Add home-eval flake check
status: completed
type: task
priority: normal
created_at: 2026-08-02T12:11:24Z
updated_at: 2026-11-07T18:58:48Z
parent: dotfiles-6f5q
---

`nix flake check` currently never evaluates anything under `home/`, so module errors and failed assertions are invisible to CI. This check evaluates a home-manager configuration with the AI-assistant modules enabled and fails when an assertion does not hold. Every later task in this epic uses it as its verification command.

It is eval-only: it forces `config.assertions` and the *names* of `config.home.file`, so no program derivations are built and the check stays fast.

**Files:**
- Create: `checks/home-eval.nix`
- Modify: `flake.nix` (add `mkHomeEvalCheck` beside `mkNixfmtCheck` around line 224; add the check to `checks.x86_64-linux` around line 276)

- [x] **Step 1: Create the check's home-manager module**

`checks/home-eval.nix`:

```nix
# Minimal home-manager configuration for the `home-eval` flake check. Enables the
# AI-assistant modules so their assertions and `home.file` mappings are evaluated
# in CI. Never activated on a real machine.
{
  home.stateVersion = "26.05";

  dotfiles.programs = {
    claude-code.enable = true;
    codex.enable = true;
    cursor.enable = true;
    beans = {
      enable = true;
      enableClaudeCodeIntegration = true;
    };
    plannotator = {
      claude-code.enable = true;
      codex.enable = true;
    };
  };
}
```

- [x] **Step 2: Add the check builder to `flake.nix`**

Insert directly after the `mkNixfmtCheck` binding (it ends with a `touch $out` heredoc around line 235), still inside the same `let`. Note the deliberate absence of any shell step — `writeText` keeps the check pure evaluation:

```nix
      # Evaluates a home-manager configuration built from `home/` and fails when any
      # module assertion does not hold. Eval-only: forces `config.assertions` and the
      # `home.file` attribute names, so no program derivations are built.
      mkHomeEvalCheck =
        system:
        let
          pkgs = nixOsPkgs { inherit system; };
          hm = mkHomeManagerSystem {
            inherit system;
            user = "check";
            directory = "/home/check";
            home = ./checks/home-eval.nix;
          };
          failed = builtins.filter (a: !a.assertion) hm.config.assertions;
        in
        if failed != [ ] then
          throw ''
            home-eval: assertions failed:
            ${pkgs.lib.concatLines (builtins.map (a: a.message) failed)}''
        else
          pkgs.writeText "home-eval" (pkgs.lib.concatLines (builtins.attrNames hm.config.home.file));
```

- [x] **Step 3: Wire it into `checks`**

In the `checks` attribute, extend the `x86_64-linux` set. Leave `aarch64-darwin` alone: `mkHomeManagerSystem` calls `nixOsPkgs` regardless of system, so a darwin variant would evaluate against the non-darwin package set.

```nix
          x86_64-linux =
            self.packages.x86_64-linux
            // linuxPkgs.dotfiles.internal.rustChecks
            // {
              nixfmt = mkNixfmtCheck linuxPkgs;
              home-eval = mkHomeEvalCheck "x86_64-linux";
            };
```

- [x] **Step 4: Verify the check passes on the current tree**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: a store path is printed. `cat` that path to see the list of `home.file` targets — it should include `.claude/settings.json` and `.claude/skills/brainstorming`.

- [x] **Step 5: Verify the check actually catches a failure**

Prove the harness works before trusting it. In `home/programs/claude-code/default.nix`, temporarily replace the body of the `assertions = [ ... ];` list with:

```nix
    assertions = [
      {
        assertion = false;
        message = "deliberate home-eval harness probe";
      }
    ];
```

Run: `nix build .#checks.x86_64-linux.home-eval --no-link`

Expected: FAIL, with `error: home-eval: assertions failed:` followed by `deliberate home-eval harness probe`.

Revert with `git checkout home/programs/claude-code/default.nix`, then re-run the build and confirm it passes again.

- [x] **Step 6: Format and commit**

```bash
nixfmt flake.nix checks/home-eval.nix
git add flake.nix checks/home-eval.nix
git commit -m "flake: add home-eval check

Evaluates a home-manager configuration from home/ and fails on any module
assertion, giving CI its first coverage of the home-manager modules.

Bean: dotfiles-d6t2"
```

## Summary of Changes

Added `checks/home-eval.nix` (base profile plus the AI-assistant modules) and `mkHomeEvalCheck` in `flake.nix`, wired into `checks.x86_64-linux.home-eval`. Deviations from the steps above, after review:

- No custom assertion filter/throw: `homeManagerConfiguration` already wraps `config` in `moduleChecks`, which throws "Failed assertions:" on any read, so the custom branch was unreachable. A failed assertion surfaces as `Failed assertions: - <message>`.
- Evaluates the whole home, not just `home.file` names: the check text records `activationPackage.drvPath` (string context discarded, so nothing in the home closure is built) followed by the `home.file` names. An eval error inside file contents or packages now fails the check too; extra eval cost measured at a few seconds over the ~31s baseline.
- Uses `hm.pkgs.writeText` rather than a third nixpkgs import.

Verified by eval on aarch64-darwin (no Linux builder): clean tree passes and lists `.claude/settings.json` and `.claude/skills/brainstorming`; a forced-false assertion and a missing attribute in `.claude/CLAUDE.md`'s text both fail; the check derivation's inputs are only stdenv and bash. `checks/` added to CLAUDE.md's project structure.
