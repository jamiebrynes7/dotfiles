# Dotfiles

Personal Nix-based system configuration for macOS and NixOS.

Freshness: 2026-10-06

## Tech Stack

- **Nix flakes** — all inputs pinned in `flake.nix`
- **nix-darwin** — macOS system configuration (`darwin/`)
- **home-manager** — user-level dotfiles and programs (`home/`)
- **direnv** — development shells for this repo and project templates
- **Rust** — Cargo workspace under `crates/` housing the `beans` issue-tracker daemon + CLI; see `crates/CLAUDE.md`

## Commands

No justfile at the repo root. Common operations:

- `nix flake check` — validate the flake; also checks Nix formatting (the `nixfmt` check) and builds/tests the Rust workspace (this is what CI runs)
- `nix flake show` — list outputs (systems, templates, lib)
- `nixfmt <file>` — format Nix files (available in the devShell)
- `cargo test --workspace` — run Rust tests directly without going through Nix (see `crates/CLAUDE.md`)
- `gh workflow run update-flake-lock.yml` — bump `flake.lock`. Manual only: this lock is the single source of truth for every machine (`templates/systems/*` pin nothing but `dotfiles.url`), so a bump here reaches the whole fleet. It opens an auto-merging PR, and re-pins the hashes that `beans` and `paseo` compute against the pinned nixpkgs. Takes an optional space-separated input filter; blank updates everything. Moving to the *next* nixpkgs release is a different job — see "Channel inputs" below.

A `.githooks/pre-commit` formatting gate (Nix + Rust) is auto-wired via `core.hooksPath` by the devShell `shellHook` — commit from inside the devShell (the `direnv` shell) so `nixfmt`/`cargo` are on `PATH`.

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
packages/            # Nix packages — built from this repo (beans-daemon) or vendored upstream binaries
```

## Conventions

### Packages

Every directory under `packages/` is auto-discovered by `flake.nix` and exposed as `pkgs.dotfiles.<dir>` — **only** there, never as a top-level `pkgs.<name>`. Reference them as `pkgs.dotfiles.claude-code`, not `pkgs.claude-code`.

Vendored upstream binaries (`claude-code`, `codex`, `cship`, `plannotator`, `sprite`) follow a fixed shape: a `hashes.json` recording the version plus a per-platform artifact name and hash, a `default.nix` that reads it, and an `update.sh` that refreshes it. `update.sh` must be idempotent — re-running it when the recorded version already matches should exit 0 without touching `hashes.json`, since `.github/workflows/auto-update.yml` runs every script nightly and opens a PR only if `packages/` changed.

Beyond that, `update.sh` should **fail** on anything it cannot resolve, including a release whose artifacts have not been uploaded yet. Exiting 0 there would pin the package indefinitely behind a green nightly, and a transient upload gap is indistinguishable from upstream renaming or dropping an artifact. `auto-update.yml` runs every script before reporting, so one failure surfaces as a red job without blocking the other packages' updates.

`paseo` is the one package built from vendored *source* rather than a prebuilt binary, because upstream ships no headless daemon artifact — every release asset is the Electron desktop app, and the npm packages still need an `npm ci` plus a native `node-pty` compile. Its `default.nix` `callPackage`s upstream's own `nix/package.nix` out of a `fetchFromGitHub` source, which makes it the repo's **only import-from-derivation package**: evaluating it builds that fetch, so eval needs network on a cold machine. Its `hashes.json` therefore also records a source hash and an `npmDepsHash` computed against *our* pinned nixpkgs (upstream's recorded hash is for theirs, and is stale at every tag besides). That hash silently rots when `flake.lock`'s nixpkgs moves; the fix is `packages/paseo/update.sh --force`. The macOS app is a separate `passthru.desktop` on the same derivation — a plain fetch of upstream's signed, notarized zip, aliased as `packages.aarch64-darwin.paseo-desktop` because Nix will not walk into a derivation's passthru from a flake output path.

`packages/paseo` is also the only package here that patches upstream source: a `postPatch` makes the daemon's `savePersistedConfig` throw rather than overwrite a `config.json` that is a symlink, because `home/programs/paseo.nix` always writes that file from the store and the daemon's atomic save would otherwise rename a temp file over it. Both anchors use `--replace-fail`, and `postInstall` greps `$out` for the sentinel, so an upstream rewrite fails the build instead of silently shipping an unguarded daemon.

Paseo plugins are packaged one directory per plugin, named after the **plugin id** — `packages/paseo-plugin-<id>/` — so `dotfiles.programs.paseo.plugins.<id>.package = pkgs.dotfiles.paseo-plugin-<id>` needs no lookup table. An external plugin whose upstream publishes no releases is pinned by commit SHA literally in its `default.nix`, with **no** `hashes.json` and **no** `update.sh`: plugin code runs unsandboxed as the daemon user, so every bump is a reviewed commit rather than a nightly auto-update PR. Omitting `update.sh` is what keeps `auto-update.yml` away from it. `nix flake check`'s `paseo-plugin-requirements` check (`packages/paseo/plugin-requirements.nix`) evaluates every `paseo-plugin-*` package's `requirements.paseo` against the pinned paseo version, so a nightly paseo bump that a plugin no longer admits goes red instead of failing at load on a host.

### Channel inputs

`nixpkgs` (`nixos-26.05`) and `nixpkgs-darwin` (`nixpkgs-26.05-darwin`) are **the same `release-26.05` branch behind two different Hydra gates**, not two package sets — each is a pointer Hydra fast-forwards once its own jobset is green, Linux for one and Darwin for the other. They can therefore differ only in staleness, never in content, which is why they are always bumped together in one PR. The Darwin pointer exists for cache hit rate and to catch Darwin breakage the Linux gate would miss; `flake.nix` builds `pkgs` per-platform from the respective input, so neither platform ever sees the other's nixpkgs.

Moving to the next release is a separate, hand-written change: `nixpkgs`, `nixpkgs-darwin`, `darwin` (`nix-darwin-26.05`) and `home-manager` (`release-26.05`) must all move in lockstep, since nix-darwin and home-manager cut a release branch per nixpkgs release.

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

### Specs

`docs/specs/` holds dated, point-in-time decision records, not living documentation. They are left as written once work lands; the code and these `CLAUDE.md` files are the source of truth. A later change of direction gets a new spec with a `Supersedes:` line rather than an edit to the old one.

### Formatting

All Nix files are formatted with `nixfmt` (the official RFC 166-style formatter). A `.githooks/pre-commit` hook blocks commits that leave `*.nix` or `*.rs` files unformatted (`nixfmt --check` / `cargo fmt --all --check`); CI's `nix flake check` remains the authoritative gate.

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
