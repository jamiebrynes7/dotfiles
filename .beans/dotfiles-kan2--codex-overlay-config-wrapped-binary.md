---
# dotfiles-kan2
title: Codex overlay config + wrapped binary
status: todo
type: feature
created_at: 2026-06-04T10:10:30Z
updated_at: 2026-06-04T10:10:30Z
parent: dotfiles-ywp9
---

Adds the `dotfiles.programs.codex.hooks` bool option (default true), renders `~/.codex/dotfiles.config.toml` from `pkgs.formats.toml` with `features.hooks`, installs a `~/.local/bin/codex` wrapper that execs `codex --profile dotfiles "$@"`, drops `pkgs.dotfiles.codex` from `home.packages`, and contributes `~/.local/bin` to PATH via the shared zsh option. Owns: home/programs/codex.nix. Lands as one commit. Depends on the zsh refactor feature.
