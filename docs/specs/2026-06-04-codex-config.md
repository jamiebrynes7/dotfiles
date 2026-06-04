# Codex managed configuration — scaffolding

**Date:** 2026-06-04
**Status:** approved design, ready for planning

## Problem

This dotfiles repo deploys Codex (`home/programs/codex.nix`: the binary, shared
`AGENTS.md`, and skills) but does not manage Codex's **configuration**. The
natural target, `~/.codex/config.toml`, is owned and rewritten by Codex itself
(auth tokens, history, local state), so it cannot be a read-only Nix symlink
without clobbering that state.

We want to manage selected Codex config declaratively from Nix without touching
the file Codex writes.

## Solution overview

Use Codex's profile-overlay mechanism. Codex (≥ 0.134.0) loads a profile from a
**separate file** `~/.codex/<name>.config.toml` and overlays it on top of
`config.toml` when invoked with `--profile <name>`. So:

- Nix renders a read-only `~/.codex/dotfiles.config.toml` overlay file.
- A wrapper binary at `~/.local/bin/codex` always execs the real Codex with
  `--profile dotfiles`, so the overlay is always active.
- Codex still owns and writes only `config.toml`; the overlay is never written
  by Codex. No clobbering.

This deliverable is **scaffolding**: the full pipeline plus a single example
knob — `dotfiles.programs.codex.hooks` (bool, default `true`) — that renders
into the overlay, proving settings flow end to end.

### Verified Codex mechanics

- Profiles are separate files `~/.codex/<name>.config.toml`; the legacy
  `[profiles.<name>]`-inside-`config.toml` table syntax was removed in 0.134.0.
- `codex --profile dotfiles` loads `config.toml`, then overlays
  `~/.codex/dotfiles.config.toml`.
- Config precedence, low → high: user `config.toml` → profile overlay → project
  `.codex/config.toml` (trusted projects only) → CLI flags. The managed overlay
  therefore overrides the user's base config but yields to per-project and
  ad-hoc CLI settings — correct "managed defaults" behavior.
- `--config`/`-c` accepts key=value pairs only (no file-path variant), so a
  rendered TOML file selected via `--profile` is the right vehicle.
- The `hooks` feature flag is `[features]\nhooks = <bool>` (`codex_hooks` is a
  deprecated alias; use `hooks`). Default is `true`.

## Work breakdown

Two independent, independently-buildable commits.

### Commit 1 — Pre-work refactor: shared `extraSessionPaths` on the zsh module

Today `home/programs/claude-code/default.nix` puts `~/.local/bin` on PATH via a
raw `programs.zsh.envExtra` export. Adding a second such export from the codex
module would duplicate the entry. Instead, give the zsh module a de-duplicating
option that any module can contribute to.

- In `home/programs/zsh.nix`, add option:

  ```nix
  options.dotfiles.programs.zsh.extraSessionPaths = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description =
      "Extra entries appended to PATH via home.sessionPath (de-duplicated).";
  };
  ```

- In that module's `config` (inside the existing `mkIf cfg.enable`):

  ```nix
  home.sessionPath = lib.unique cfg.extraSessionPaths;
  ```

  The module system concatenates contributions from all modules into one list;
  `lib.unique` collapses duplicates so the directory appears in PATH exactly
  once regardless of how many modules ask for it.

- In `home/programs/claude-code/default.nix`: remove the
  `programs.zsh.envExtra` PATH export and replace it with

  ```nix
  dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ];
  ```

Note: `extraSessionPaths` only takes effect when the zsh module is enabled
(base profile, always on). This is acceptable because the PATH sourcing depends
on home-manager's zsh integration (`hm-session-vars.sh`) anyway.

**Validation:**
- `nix flake check` passes.
- After switch, `$PATH` contains `$HOME/.local/bin` exactly once.
- `which claude` resolves to `~/.local/bin/claude` (claude-code still works).

### Commit 2 — Codex overlay config + wrapped binary

In `home/programs/codex.nix`:

- Add option:

  ```nix
  options.dotfiles.programs.codex.hooks = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable Codex lifecycle hooks ([features].hooks) via the dotfiles profile overlay.";
  };
  ```

- Render the overlay file with `pkgs.formats.toml` (correct TOML, scales to
  nested tables later):

  ```nix
  codexConfig = (pkgs.formats.toml { }).generate "codex-dotfiles.toml" {
    features.hooks = cfg.hooks;
  };
  ```

  Deploy it: `home.file.".codex/dotfiles.config.toml".source = codexConfig;`
  (added to the existing `home.file` attrset alongside `AGENTS.md` and skills).

- Add a wrapper script and install it to `~/.local/bin/codex`:

  ```nix
  codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
    exec ${pkgs.dotfiles.codex}/bin/codex --profile dotfiles "$@"
  '';
  ```

  ```nix
  home.activation.codexStableLink =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.local/bin
      install -m755 ${codexWrapper} "$HOME/.local/bin/codex"
    '';
  ```

- Remove `pkgs.dotfiles.codex` from `home.packages` so only the wrapper named
  `codex` is on PATH. The wrapper references the store path by absolute path, so
  there is no recursion. Skills and `AGENTS.md` wiring are unchanged.

- Contribute `~/.local/bin` to PATH via the shared zsh option from Commit 1:

  ```nix
  dotfiles.programs.zsh.extraSessionPaths = [ "$HOME/.local/bin" ];
  ```

**Validation:**
- `nix flake check` passes.
- After switch:
  - `~/.codex/dotfiles.config.toml` exists, is a Nix-store symlink, and contains
    `[features]` with `hooks = true`.
  - `which codex` → `~/.local/bin/codex`; the script contains the
    `--profile dotfiles` exec line.
  - `~/.codex/config.toml` is untouched — not a symlink, still user-writable.
  - Setting `dotfiles.programs.codex.hooks = false` and rebuilding flips the
    generated TOML to `hooks = false`, proving the knob flows end to end.

## Known limitation

The wrapper unconditionally injects `--profile dotfiles`. If a user runs
`codex --profile other` themselves, the command line carries two `--profile`
flags. Codex's resolution of duplicate `--profile` flags (last-wins vs. error)
is not verified here. For this scaffolding deliverable this is a **documented
limitation**: ad-hoc profile switching may require invoking the unwrapped
binary at `${pkgs.dotfiles.codex}/bin/codex` directly. Solving it (e.g. only
injecting the flag when none is present) is deferred follow-up.

## Out of scope

- Exposing model/sandbox/approval/MCP settings as options (only the `hooks`
  example knob ships now; the `pkgs.formats.toml` renderer makes adding them
  later straightforward).
- Per-host overridability of the values (fixed in-module for now).
- Resolving the duplicate-`--profile` limitation above.
