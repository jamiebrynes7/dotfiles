---
# dotfiles-cdza
title: Add codex CLI package to packages/
status: completed
type: task
priority: normal
created_at: 2026-06-01T12:48:53Z
updated_at: 2026-06-01T13:08:04Z
---

Add a Nix package for the OpenAI Codex CLI (`openai/codex`) under `packages/`, so it can be installed via this repo's flake outputs like the other packages.

## Context

`packages/` is auto-discovered by `flake.nix` (`discoverPackages ./packages`). The `cship` package is the closest model: it fetches a prebuilt release binary from GitHub via `fetchurl`, with a `hashes.json` (version + per-platform artifact name & sha256) consumed by `default.nix`, and an `update.sh` helper that refreshes `hashes.json` for a given/latest tag.

Codex CLI is distributed as prebuilt release artifacts on `github.com/openai/codex`, so the same fetchurl-from-releases approach should apply. Confirm the artifact naming and archive format (likely `.tar.gz` per platform, which differs from cship's bare binary and will need an unpack/install step) before finalising.

## Todos

- [x] Inspect the latest `openai/codex` GitHub release to confirm artifact names, archive format, and supported platforms (aarch64/x86_64 darwin + linux)
- [x] Create `packages/codex/default.nix` modeled on `packages/cship/default.nix` (fetchurl from releases, read `hashes.json`, install binary to `$out/bin/codex`)
- [x] Create `packages/codex/hashes.json` with version + per-platform artifact/hash entries
- [x] Create `packages/codex/update.sh` modeled on `packages/cship/update.sh` (REPO=openai/codex, correct PLATFORM_MAP and URL pattern)
- [x] Verify the package builds: `nix build .#codex` on the current platform (aarch64-darwin); x86_64-linux derivation evaluates cleanly
- [x] Run `nix flake check` (exit 0) and `nixfmt` on new Nix files
- [x] Decide whether to wire codex into a home-manager profile/program, or leave as a standalone package output (ask if unsure)

## Summary of Changes

Added the OpenAI Codex CLI as a prebuilt-binary Nix package plus an unwired home-manager module.

- `packages/codex/{default.nix,hashes.json,update.sh}` — modeled on `packages/cship`. Fetches `codex-<target>.tar.gz` from `openai/codex` releases (note the `rust-v<version>` tag scheme), unpacks the single-binary tarball (`sourceRoot = "."`), installs as `$out/bin/codex`. License Apache-2.0, `mainProgram = "codex"`. Pinned at 0.135.0; `update.sh` bumps it.
- `home/programs/codex.nix` — `dotfiles.programs.codex` module, defaults off and not enabled in any profile (enable downstream, like claude-code).

Decision: bare binary only — no bundled `rg`/`bubblewrap`; codex relies on ambient tools (vendoring Codex's prebuilt `rg` would need autoPatchelfHook on Linux for no benefit).

Validation: `nix flake check` exit 0; builds on aarch64-darwin (`codex-cli 0.135.0`); x86_64-linux derivation evaluates; nixfmt clean. Subagent + user review passed.
