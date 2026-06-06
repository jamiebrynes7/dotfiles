# Dotfiles

Personal Nix-based system configuration for macOS and NixOS.

Freshness: 2026-05-30

## Tech Stack

- **Nix flakes** — all inputs pinned in `flake.nix`
- **nix-darwin** — macOS system configuration (`darwin/`)
- **home-manager** — user-level dotfiles and programs (`home/`)
- **direnv** — development shells for this repo and project templates
- **Rust** — Cargo workspace under `crates/` housing the `beans` issue-tracker daemon + CLI; see `crates/CLAUDE.md`

## Commands

No justfile at the repo root. Common operations:

- `nix flake check` — validate the flake; also builds and tests the Rust workspace (this is what CI runs)
- `nix flake show` — list outputs (systems, templates, lib)
- `nixfmt <file>` — format Nix files (available in the devShell)
- `cargo test --workspace` — run Rust tests directly without going through Nix (see `crates/CLAUDE.md`)

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
crates/              # Rust workspace: beansd + beansctl + beansd-rpc — see crates/CLAUDE.md
packages/            # Nix packages built from this repo (e.g. beans-daemon)
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

All Nix files are formatted with `nixfmt` (the official RFC 166-style formatter).

### Commit messages

Subject format is `<area>: <imperative summary>`. The area names the part of the repo that changed — there are no Conventional Commits type prefixes (`feat:`, `fix:`, `refactor:`, `chore:`).

- Scope to the crate/subdir when the change lives there: `crates beansd:`, `crates beansd-rpc:`, `home/programs/<tool>:`.
- Use the parent area when a change spans several: `crates:`, `packages:`, `flake.lock:`.
- `beans:` is for issue-tracker housekeeping (creating, closing, archiving beans) — not for `beansd`/`beansctl` code.
- When a bean tracks the work, reference its id in the commit body (not the subject) as a trailer: a `Bean: <id>` line at the end of the message, e.g.

  ```
  crates beansd: extract resolve_active helper

  Bean: dotfiles-n7m9
  ```

## Boundaries

`home/lib/ai/global-instructions.md` is deployed verbatim as the **global** agent instructions to `~/.claude/CLAUDE.md` (via the claude-code module) and `~/.codex/AGENTS.md` (via the codex module). Cursor is not wired up to it. Edits there affect every project for those assistants, not just this repo. Keep it assistant-agnostic; repo-specific guidance belongs in this file instead.
