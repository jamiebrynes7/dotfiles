# Codex hook declarations + top-level plannotator module

**Date:** 2026-06-04
**Status:** Spec — ready for planning

## Goal

Two related capabilities for the Nix dotfiles:

1. Let `home/programs/codex` **declare codex lifecycle hooks** that render to a
   documented codex discovery location (`~/.codex/hooks.json`).
2. Add a **plannotator option** that wires the plannotator plan-review hook,
   inverted into a single top-level module shared by both codex and claude-code.

Replicates the plannotator codex setup
(<https://github.com/backnotprop/plannotator/blob/main/apps/codex/README.md>)
on top of codex's hook mechanism
(<https://developers.openai.com/codex/hooks>).

## Background

- `home/programs/codex.nix` already renders `~/.codex/dotfiles.config.toml` from
  `pkgs.formats.toml` and wraps the binary to exec `codex --profile dotfiles`.
  Today its `hooks` option is a **bool** feeding `[features].hooks` in that
  overlay — there is no hook-*declaration* mechanism yet.
- `home/programs/claude-code/hooks/types.nix` defines the hook submodules +
  `mergeHooks`; `home/programs/claude-code/plannotator/default.nix` wires a hook,
  ships a wrapper (`remote`/`port`), and ships the `plannotator-user-code-review`
  skill.
- Codex discovers hooks from `~/.codex/hooks.json` or inline `[hooks]` in
  `~/.codex/config.toml`. The hook JSON shape is `event → matcher group →
  handlers`, identical to claude-code's.
- `dotfiles.programs.claude-code.plannotator.enable` is **not set anywhere in
  this repo** — it is enabled in downstream system repos created from
  `templates/systems/`.

## Decisions (locked via options review)

- **Discovery file:** declared codex hooks render to a managed
  `~/.codex/hooks.json`. The `[features] hooks = true` feature flag stays in the
  `dotfiles.config.toml` overlay.
- **Hook types:** codex gets its **own** local hook types (Approach 1) — no
  shared hooks-types abstraction with claude-code. The two event enums are
  similar but allowed to diverge.
- **Plannotator (inverted):** a single top-level `home/programs/plannotator/`
  module owns the shared package/wrapper/skill and fans out per enabled
  assistant. The differing hook event is a per-assistant constant.
- **Option rename is a clean break** (no `mkRenamedOptionModule` alias);
  downstream repos update their option paths. Documented as a migration note.
- **`statusMessage`** is included as an optional codex-native command field.

## Components

### 1. Codex-local hook types — `home/programs/codex/hooks/types.nix` (new)

Near-copy of `home/programs/claude-code/hooks/types.nix`, adapted for codex.

- `hookEvents` (codex set): `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`,
  `SubagentStart`, `SubagentStop`, `Stop`.
- `hookCommandType` submodule:
  - `type`: `enum [ "command" ]`, default `"command"`.
  - `command`: `str` (required).
  - `timeout`: `nullOr int`, default `null`.
  - `statusMessage`: `nullOr str`, default `null` (codex-native UI text).
- `hookType` submodule: `enable` (mkEnableOption), `event`
  (`enum hookEvents`, required), `matcher` (`nullOr str`, default `null`),
  `hooks` (`listOf hookCommandType`).
- `mergeHooks hookDefs`: filters to enabled hooks, drops `null` optional fields
  (`timeout`, `statusMessage`) from each command, groups by event, and returns
  `{ <Event> = [ { matcher?; hooks = [ ... ]; } ]; }` — the same transform shape
  as claude-code's `mergeHooks`.
- Exports `{ inherit hookEvents hookCommandType hookType mergeHooks; }`.

### 2. Codex module — `home/programs/codex/default.nix` (moved from `codex.nix`)

Convert the single file into a directory module (`home/programs/` auto-imports
subdirectories). Fix relative paths (`../lib` → `../../lib`). Behavior changes:

- `import ./hooks/types.nix { inherit lib; }` → `hookTypes`.
- **Rename option** `hooks` (bool) → **`enableHooks`** (`bool`, default `true`),
  description references `[features].hooks`. The overlay becomes
  `features.hooks = cfg.enableHooks;`.
- **Add option** `hooks` = `attrsOf hookTypes.hookType`, default `{}`,
  description "Named codex hook definitions rendered to ~/.codex/hooks.json".
- Compute `mergedHooks = hookTypes.mergeHooks cfg.hooks;`.
- **Render hooks.json** conditionally: when `mergedHooks != {}`, add
  `".codex/hooks.json".source = pkgs.writeText "codex-hooks.json"
  (builtins.toJSON { hooks = mergedHooks; });` to `home.file` (via
  `lib.optionalAttrs`). When no hooks are enabled, the file is omitted entirely.
- **Assertion:** `cfg.hooks == {} || cfg.enableHooks` with message that declared
  codex hooks require `enableHooks = true` or they will never fire. (Added to the
  existing `assertions` list alongside the skills-conflict assertion.)

Everything else (skills, AGENTS.md, overlay file, wrapper, stable link,
`extraSessionPaths`) is unchanged apart from the path fixups.

### 3. Top-level plannotator — `home/programs/plannotator/default.nix` (new)

Owns all shared plannotator concerns; fans out to assistants.

- `plannotatorWrapper = pkgs.writeShellScriptBin "plannotator"` — moved verbatim
  from the old claude-code module: exports `PLANNOTATOR_REMOTE=1` when
  `cfg.remote`, `PLANNOTATOR_PORT` when `cfg.port != null`, then
  `exec ${pkgs.dotfiles.plannotator}/bin/plannotator "$@"`.
- Options under `dotfiles.programs.plannotator`:
  - `remote`: `bool`, default `false`.
  - `port`: `nullOr int`, default `null`.
  - `claude-code.enable`: mkEnableOption "plannotator for claude-code".
  - `codex.enable`: mkEnableOption "plannotator for codex".
- `config = mkMerge [ ... ]`:
  - **Shared** (`mkIf (cfg.claude-code.enable || cfg.codex.enable)`):
    `home.packages = [ plannotatorWrapper ];`
  - **claude-code** (`mkIf cfg.claude-code.enable`):
    - `dotfiles.programs.claude-code.skillsDirs = [ ./skills ];`
    - `dotfiles.programs.claude-code.hooks.plannotator-review = { enable = true;
      event = "PermissionRequest"; matcher = "ExitPlanMode"; hooks = [{ type =
      "command"; command = "${plannotatorWrapper}/bin/plannotator"; timeout =
      345600; }]; };`
  - **codex** (`mkIf cfg.codex.enable`):
    - `dotfiles.programs.codex.skillsDirs = [ ./skills ];`
    - `dotfiles.programs.codex.hooks.plannotator-review = { enable = true;
      event = "Stop"; hooks = [{ type = "command"; command =
      "${plannotatorWrapper}/bin/plannotator"; timeout = 345600; }]; };`
      (no `matcher`.)

The `plannotator-user-code-review` skill directory moves from
`home/programs/claude-code/plannotator/skills/` to
`home/programs/plannotator/skills/`.

### 4. Remove old claude-code plannotator + rewire

- Delete `home/programs/claude-code/plannotator/` (its `default.nix`; skills
  moved per §3).
- In `home/programs/claude-code/default.nix`, change
  `imports = [ ./hooks ./plannotator ./cship ];` → `imports = [ ./hooks ./cship ];`.

## Data flow

```
cfg.hooks (attrset) ──mergeHooks──► ~/.codex/hooks.json  { "hooks": { "Stop": [ { hooks: [...] } ] } }
cfg.enableHooks ─────────────────► ~/.codex/dotfiles.config.toml  [features] hooks = true
plannotator.codex.enable ────────► injects cfg.hooks.plannotator-review (event = Stop)

codex (wrapper: --profile dotfiles)
  ├─ loads dotfiles.config.toml overlay  → [features].hooks enabled
  └─ discovers ~/.codex/hooks.json        → on Stop, runs plannotatorWrapper → plan review
```

## Edge cases & error handling

- **Empty hooks:** `~/.codex/hooks.json` is not written when no hook is enabled.
- **Declared-but-disabled:** assertion fails the build if `cfg.hooks` is
  non-empty while `cfg.enableHooks = false`.
- **Skill name conflicts:** the moved plannotator skill participates in codex's
  and claude-code's existing skills-conflict assertions.
- **Both assistants enabled:** `home.packages` gets the wrapper once (shared
  `mkIf`); each assistant's `hooks.plannotator-review` is independent.

## Migration (breaking change for downstream system repos)

Downstream repos that set the old option must update:

```nix
# before
dotfiles.programs.claude-code.plannotator = {
  enable = true;
  remote = true;        # optional
  port = 1234;          # optional
};

# after
dotfiles.programs.plannotator = {
  claude-code.enable = true;
  remote = true;        # optional, now shared
  port = 1234;          # optional, now shared
};
# and, to enable codex plannotator:
dotfiles.programs.plannotator.codex.enable = true;
```

No alias is provided; the old path is removed.

## Validation

- `nix flake check` — builds both home modules and exercises all assertions
  (this is what CI runs).
- `nixfmt` on all new/changed `.nix` files.
- Manual spot-check after a switch: `~/.codex/hooks.json` contains the `Stop`
  plannotator hook; `~/.codex/dotfiles.config.toml` has `[features] hooks =
  true`; a live codex turn fires the plannotator review on `Stop`.

## Out of scope

- Sharing hook *types* between codex and claude-code (explicitly rejected in
  options review).
- `commandWindows` hook field (this config targets macOS/NixOS).
- Repo-local (`<repo>/.codex/hooks.json`) hook declarations.
