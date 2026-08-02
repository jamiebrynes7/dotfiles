---
# dotfiles-8ici
title: Validate rendered plugins in CI
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:18:09Z
updated_at: 2026-08-02T13:59:31Z
parent: dotfiles-gq4t
blocked_by:
    - dotfiles-36nb
---

Claude Code owns the plugin manifest schema, so an upgrade could reject a manifest this repo generates. Without a check, the symptom is silent: the plugin simply stops loading and the skills disappear from sessions. `claude plugin validate` runs offline against a directory (verified: exit 0, warning-only output for a minimal manifest), so it works inside a Nix build sandbox.

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add the check builder**

Insert after `mkHomeEvalCheck` in the same `let` block:

```nix
      # Runs Claude Code's own manifest validator over every rendered plugin, so a
      # schema change in a claude-code upgrade fails CI instead of silently
      # disabling a plugin. `claude plugin validate` needs no network; HOME is set
      # because it reads user config paths on startup.
      mkPluginValidateCheck =
        system:
        let
          pkgs = nixOsPkgs { inherit system; };
          hm = mkHomeManagerSystem {
            inherit system;
            user = "check";
            directory = "/home/check";
            home = ./checks/home-eval.nix;
          };
          pluginPaths = lib.mapAttrsToList (_: entry: entry.source) (
            lib.filterAttrs (
              target: _: lib.hasPrefix ".claude/skills/df-" target
            ) hm.config.home.file
          );
        in
        pkgs.runCommandLocal "plugin-validate" { nativeBuildInputs = [ pkgs.dotfiles.claude-code ]; } ''
          export HOME=$TMPDIR
          for plugin in ${lib.escapeShellArgs pluginPaths}; do
            echo "validating $plugin"
            claude plugin validate "$plugin"
          done
          touch $out
        '';
```

`lib` is not otherwise bound at this level in `flake.nix` — use `inputs.nixpkgs.lib` if the bare `lib` does not resolve, matching how the file already reaches for `inputs.nixpkgs.lib.modules.importApply`.

- [ ] **Step 2: Wire it into `checks`**

```nix
          x86_64-linux =
            self.packages.x86_64-linux
            // linuxPkgs.dotfiles.internal.rustChecks
            // {
              nixfmt = mkNixfmtCheck linuxPkgs;
              home-eval = mkHomeEvalCheck "x86_64-linux";
              plugin-validate = mkPluginValidateCheck "x86_64-linux";
            };
```

- [ ] **Step 3: Verify the check passes**

Run: `nix build .#checks.x86_64-linux.plugin-validate --no-link -L`

Expected: the log shows one `validating /nix/store/...-plugin-cc-df-base` line per plugin (three of them), each followed by `✔ Validation passed`, and the build succeeds.

- [ ] **Step 4: Verify the check catches a bad manifest**

In `home/lib/ai/plugins/default.nix`, temporarily give the manifest an invalid name — plugin names must be kebab-case with no spaces:

```nix
          name = "not a valid name";
```

Run: `nix build .#checks.x86_64-linux.plugin-validate --no-link -L`

Expected: FAIL, with validation errors naming the offending field. Revert the edit and re-run to confirm it passes again.

- [ ] **Step 5: Verify the full flake check**

Run: `nix flake check`

Expected: passes, now covering nixfmt, the Rust workspace, packages, `home-eval` and `plugin-validate`.

- [ ] **Step 6: Format and commit**

```bash
nixfmt flake.nix
git add flake.nix
git commit -m "flake: validate rendered plugins in CI

Runs claude plugin validate over each rendered plugin so manifest schema
drift fails the build rather than silently disabling a plugin.

Bean: dotfiles-8ici"
```
