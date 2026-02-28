# Dotfiles

Personal Nix-based system configuration for macOS and NixOS.

Freshness: 2026-02-28

## Tech Stack

- **Nix flakes** — all inputs pinned in `flake.nix`
- **nix-darwin** — macOS system configuration (`darwin/`)
- **home-manager** — user-level dotfiles and programs (`home/`)
- **devenv + direnv** — development shells for this repo and project templates

## Commands

No justfile at the repo root. Common operations:

- `nix flake check` — validate the flake (runs all checks)
- `nix flake show` — list outputs (systems, templates, lib)
- `nixfmt-classic <file>` — format Nix files (available in the devShell)

Host-specific build/switch commands live in downstream system repos created from `templates/systems/`.

## Project Structure

```
flake.nix            # Inputs, overlays, lib (mkDarwin, mkNixosSystem, mkHomeManagerSystem), templates, devShell
darwin/
  default.nix        # nix-darwin module: Nix settings, keyboard, sudo
  brew.nix           # Homebrew casks, organised by profile (default/social/productivity/gaming)
home/
  default.nix        # Auto-discovers program modules from home/programs/
  profiles.nix       # base (default on) and desktop (default off) profiles
  programs/          # One module per tool — see "Program module pattern" below
  lib/ai/            # Shared AI assistant commands, skills, and tools — see home/lib/ai/CLAUDE.md
templates/
  projects/          # go, typescript — scaffolded via `spark`
  systems/           # darwin, nixos, home-manager
modules/             # Shared NixOS/nix-darwin modules (currently empty)
```

## Conventions

### Program module pattern

Every file or subdirectory in `home/programs/` is auto-imported by `home/default.nix`. Modules follow this shape:

```nix
{ config, lib, ... }:
let cfg = config.dotfiles.programs.<name>;
in {
  options.dotfiles.programs.<name> = {
    enable = lib.mkEnableOption "Enable <name>";
  };
  config = lib.mkIf cfg.enable { ... };
}
```

Profiles in `home/profiles.nix` set `dotfiles.programs.<name>.enable = true` to wire programs on.

### Profile system

Defined in `home/profiles.nix` under `dotfiles.profiles`:

- **base** (default: `true`) — core CLI tools: atuin, bat, direnv, git, gh, nvim, zsh, etc.
- **desktop** (default: `false`) — GUI programs: alacritty, zellij

### AI library

`home/lib/ai/` is a shared library (not a NixOS module) providing commands and skills for Claude Code and Cursor. It uses variant prefixes (`cc:`, `cursor:`) in YAML frontmatter to produce assistant-specific output from single source files. See `home/lib/ai/CLAUDE.md` for details.

### Formatting

All Nix files are formatted with `nixfmt-classic`.

## Boundaries

`home/programs/claude-code/CLAUDE.md` is deployed as the **global** `~/.claude/CLAUDE.md` via home-manager. Edits there affect every project, not just this repo. Repo-specific guidance belongs in this file instead.
