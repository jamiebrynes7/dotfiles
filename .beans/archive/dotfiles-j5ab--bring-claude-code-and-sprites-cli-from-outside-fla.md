---
# dotfiles-j5ab
title: Bring claude-code and sprites-cli from outside flake into packages/ directory
status: completed
type: task
priority: normal
created_at: 2026-06-06T08:33:47Z
updated_at: 2026-08-02T14:01:52Z
---

Vendor the two external tool flakes (`claude-code-native-nix`, `sprite-cli-nix`) into `packages/` so they follow the same `default.nix` + `hashes.json` + `update.sh` convention as `codex`/`cship`/`plannotator`, and drop the flake inputs.

## Decisions

- Expose as `pkgs.dotfiles.*` only — no top-level overlay aliases. Downstream system repos referencing `pkgs.sprite` / `pkgs.claude-code` must be updated separately.
- Delete the `update-flake-inputs` job from `.github/workflows/auto-update.yml`; `update-packages` already loops `packages/*/update.sh`.
- Package dir named `sprite` to match its `pname`/`mainProgram` (the binary is `sprite`).

## Todo

- [x] Add `packages/claude-code/` (default.nix, hashes.json, update.sh)
- [x] Add `packages/sprite/` (default.nix, hashes.json, update.sh)
- [x] Remove `claude-code` and `sprites-cli` flake inputs and their overlays
- [x] Point `home/programs/claude-code` at `pkgs.dotfiles.claude-code`
- [x] Delete the `update-flake-inputs` job from auto-update.yml
- [x] Verify with `nix flake check`

## Summary of Changes

Vendored both external tool flakes into `packages/`, following the existing `default.nix` + `hashes.json` + `update.sh` convention.

- **`packages/claude-code/`** — ported from `github:jamiebrynes7/claude-code-native-nix`. Fetches the prebuilt binary from Anthropic's GCS bucket; `autoPatchelfHook` on Linux, `makeWrapper` sets `CLAUDE_EXECUTABLE_PATH`/`DISABLE_AUTOUPDATER`. `update.sh` reads the release `manifest.json` and converts its hex checksums to SRI, so it needs no downloads.
- **`packages/sprite/`** — ported from `github:jamiebrynes7/sprite-cli-nix`. `update.sh` prefers the stable channel and falls back to rc; this bumped the pin from `v0.0.1-rc43` to `v0.0.1-rc47`, since the vendored flake was stale.
- Removed the `claude-code` and `sprites-cli` flake inputs, their overlays, and their transitive `flake-utils`/`systems` lock entries.
- `home/programs/claude-code` now references `pkgs.dotfiles.claude-code`.
- Deleted the `update-flake-inputs` job from `.github/workflows/auto-update.yml` — it existed solely to bump these two inputs, and `update-packages` already loops `packages/*/update.sh`.
- Documented the `pkgs.dotfiles.*`-only convention and the vendored-package shape in `CLAUDE.md`.

Verified: `nix flake check` passes; both packages build and run (`claude 2.1.220`, `sprite v0.0.1-rc47`); the `aarch64-darwin` variants evaluate; a home-manager config with `claude-code` enabled evaluates; both `update.sh` scripts are idempotent on re-run.

Follow-ups from review: dotfiles-0i4a, dotfiles-35eb.
