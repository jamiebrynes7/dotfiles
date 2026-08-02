---
# dotfiles-d6t2
title: Add home-eval flake check
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:11:24Z
updated_at: 2026-08-02T12:12:12Z
parent: dotfiles-6f5q
---

`nix flake check` currently never evaluates anything under `home/`, so module errors and failed assertions are invisible to CI. This check evaluates a home-manager configuration with the AI-assistant modules enabled and fails when an assertion does not hold. Every later task in this epic uses it as its verification command.

It is eval-only: it forces `config.assertions` and the *names* of `config.home.file`, so no program derivations are built and the check stays fast.

**Files:**
- Create: `checks/home-eval.nix`
- Modify: `flake.nix` (add `mkHomeEvalCheck` beside `mkNixfmtCheck` around line 224; add the check to `checks.x86_64-linux` around line 276)

- [ ] **Step 1: Create the check's home-manager module**

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

- [ ] **Step 2: Add the check builder to `flake.nix`**

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

- [ ] **Step 3: Wire it into `checks`**

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

- [ ] **Step 4: Verify the check passes on the current tree**

Run: `nix build .#checks.x86_64-linux.home-eval --no-link --print-out-paths`

Expected: a store path is printed. `cat` that path to see the list of `home.file` targets — it should include `.claude/settings.json` and `.claude/skills/brainstorming`.

- [ ] **Step 5: Verify the check actually catches a failure**

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

- [ ] **Step 6: Format and commit**

```bash
nixfmt flake.nix checks/home-eval.nix
git add flake.nix checks/home-eval.nix
git commit -m "flake: add home-eval check

Evaluates a home-manager configuration from home/ and fails on any module
assertion, giving CI its first coverage of the home-manager modules.

Bean: dotfiles-d6t2"
```
