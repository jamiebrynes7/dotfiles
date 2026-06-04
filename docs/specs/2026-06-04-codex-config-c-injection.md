# Codex managed configuration — `-c` injection (scaffolding, revised)

**Date:** 2026-06-04
**Status:** approved design, ready for planning
**Supersedes:** `2026-06-04-codex-config.md` (the `--profile` overlay approach,
which was found to be broken — see Problem below).

## Problem

This dotfiles repo deploys Codex (`home/programs/codex/default.nix`: the binary,
shared `AGENTS.md`, skills, and `hooks.json`) but we want to manage selected Codex
*config* declaratively from Nix.

The prior spec (`2026-06-04-codex-config.md`) proposed a `--profile dotfiles` overlay
file rendered read-only by Nix. That is **broken**. When a profile is active, Codex
treats the profile file `~/.codex/<name>.config.toml` as the "active user layer" and
writes runtime state there — model selection from `/model`,
`[tui.model_availability_nux]` counters, and service-tier. Those writes target our
read-only Nix-store symlink and fail. (Verified against the Codex source: directory
trust always writes to base `config.toml`, but NUX/model/tier follow the active user
layer, which is the profile when one is selected.)

So we cannot point Codex at a read-only Nix file in any layer Codex writes to. We
need a vehicle for managed settings that lives outside every Codex-written file.

## Codex config layers (verified, low → high precedence)

| Layer | Prec | File | Codex writes to it? |
|---|---|---|---|
| System | 10 | `/etc/codex/config.toml` (hardcoded, not env-overridable) | No — read-only by design |
| User (base) | 20 | `~/.codex/config.toml` | Yes (trust always; NUX/model/tier when no profile) |
| User (profile) | 21 | `~/.codex/<name>.config.toml` | Yes — clobbered the old symlink |
| Project | 25 | `<repo>/.codex/config.toml` (trusted dirs only) | No |
| CLI `-c` (SessionFlags) | 30 | session-only, not persisted | n/a |

## Solution overview

Inject managed settings as CLI `-c key=value` overrides from the existing
`~/.local/bin/codex` wrapper. `-c` flags are a session-only layer (precedence 30) —
Codex never persists them to any file, so there is nothing read-only to clobber and
`~/.codex/config.toml` stays fully Codex-owned (trust/NUX/model writes work
normally).

- Drop the `~/.codex/dotfiles.config.toml` overlay file and the `--profile dotfiles`
  flag entirely.
- The wrapper execs the real Codex with generated `-c` flags rendered from a Nix
  attrset of managed settings.
- The wrapper at `~/.local/bin/codex` stays (it is the vehicle for the flags and
  keeps `codex` off the bare PATH).
- `AGENTS.md`, `skills/`, and `hooks.json` symlinks are unchanged — Codex reads,
  never writes, those.

This is **scaffolding**: the full pipeline plus a single example knob —
`dotfiles.programs.codex.enableHooks` (bool, default `true`, already declared) —
that renders into a `-c` flag, proving settings flow end to end.

### Relationship to the prior spec

The prior spec shipped in three earlier commits: the shared `extraSessionPaths` zsh
refactor, the `~/.local/bin` PATH wiring, and the codex module with the overlay +
wrapper. This spec **keeps the first two as-is** and reworks only the third: the
overlay file and `--profile` flag are removed and replaced with `-c` injection.

### Accepted tradeoff: precedence

`-c` flags sit at precedence 30, **above** a project's `.codex/config.toml` (25), so
managed values are *enforced* rather than overridable per-project defaults. This is
fine for the only current knob (`features.hooks`). If a future managed key genuinely
needs to yield to a project's pin (e.g. `model`), the precedence vehicle can be
revisited then. (Other vehicles considered and rejected: the System layer
`/etc/codex/config.toml` is read-only and below-project but requires a system module
and is not env-overridable; an activation-time merge into `~/.codex/config.toml`
gives defaults precedence but is stateful/imperative. Both were rejected in favor of
the simpler, pure-home-manager `-c` route.)

## Work breakdown

Single commit in `home/programs/codex/default.nix`.

### Render managed settings as `-c` args

Replace the overlay-file renderer with a dotted-key attrset and a flattener so the
pattern scales past the one knob:

```nix
managedConfig = {
  "features.hooks" = lib.boolToString cfg.enableHooks;
};
configArgs = lib.concatStringsSep " "
  (lib.mapAttrsToList (k: v: "-c ${lib.escapeShellArg "${k}=${v}"}") managedConfig);
```

- `lib.boolToString` yields `"true"`/`"false"`, which parse as TOML bools unquoted.
- `lib.escapeShellArg "features.hooks=true"` → `'features.hooks=true'`, safe in the
  shell. (Future string-valued settings carry their own TOML quotes inside the
  value, e.g. `model = ''"gpt-5"''`; out of scope here.)

### Wrapper injects `-c` instead of `--profile`

```nix
codexWrapper = pkgs.writeShellScript "codex-wrapper" ''
  exec ${pkgs.dotfiles.codex}/bin/codex ${configArgs} "$@"
'';
```

The `home.activation.codexStableLink` install of the wrapper to `~/.local/bin/codex`
is unchanged.

### Remove the overlay file

Delete the `codexConfig = (pkgs.formats.toml { }).generate …` binding and the
`".codex/dotfiles.config.toml".source = codexConfig;` entry from `home.file`.
home-manager removes the now-orphaned `~/.codex/dotfiles.config.toml` symlink
automatically on the next switch — no manual cleanup.

## Validation

- `nix flake check` passes.
- After switch:
  - `which codex` → `~/.local/bin/codex`; the script body contains
    `-c 'features.hooks=true'` and no `--profile`.
  - `~/.codex/dotfiles.config.toml` no longer exists.
  - `~/.codex/config.toml` is untouched — not a symlink, still user-writable; running
    `/model` or trusting a directory persists there without error.
  - Setting `dotfiles.programs.codex.enableHooks = false` and rebuilding regenerates
    the wrapper with `-c 'features.hooks=false'`, proving the knob flows end to end.

## Known limitation

If a user passes their own `-c <same-key>=…` at runtime, it collides with the
wrapper's flag on that key; Codex's session-flag merge is last-wins, so the relative
order decides. In practice users rarely override `features.hooks` ad hoc. Invoking
the unwrapped binary at `${pkgs.dotfiles.codex}/bin/codex` bypasses all injected
flags if needed.

## Out of scope

- Exposing model/sandbox/approval/MCP settings as options (only the `enableHooks`
  example knob ships now; the dotted-key `managedConfig` attrset makes adding scalar
  settings straightforward).
- Per-host overridability of the values (fixed in-module for now).
- "Managed = defaults" precedence (below project config). Deferred; would require the
  System-layer or activation-merge vehicles rejected above.
