---
# dotfiles-puhw
title: Adopt treefmt for repo-wide formatting (Nix + Rust)
status: todo
type: task
created_at: 2026-11-05T13:48:41Z
updated_at: 2026-11-05T13:48:41Z
---

**Spec:** `docs/specs/2026-11-05-treefmt.md` (all sections)

## What to build

Formatting for the repository is declared once, in a treefmt-nix module that covers exactly today's languages: Nix through nixfmt, and Rust through rustfmt from the pinned rust-overlay toolchain, with the edition read from the workspace `Cargo.toml`. That one configuration drives:

- a single `treefmt` flake check over a source filtered to the declared extensions, replacing the `nixfmt` and `rust-fmt` checks;
- `nix fmt`, through the `formatter` output;
- `treefmt` in the repository's devShell;
- the pre-commit hook, which builds the `treefmt` check on every commit instead of calling each formatter.

Docs- and beans-only PRs still build no formatting check in CI.

## Acceptance criteria

- [ ] `nix fmt` (and `treefmt` in the devShell) formats the tree, and running it on the base tree changes no files
- [ ] `checks.<system>.treefmt` exists and passes on both `aarch64-darwin` and `x86_64-linux`; the `nixfmt` and `rust-fmt` checks no longer exist, and every other check name is unchanged
- [ ] A deliberately misformatted `.nix` file, and separately a misformatted `.rs` file, each fail the `treefmt` check, and each blocks a commit through the pre-commit hook
- [ ] The pre-commit hook no longer filters staged files by extension or calls formatters directly, and never modifies the working tree
- [ ] Changing only a Markdown or bean file leaves the `treefmt` check's `drvPath` unchanged; changing a `.nix` or `.rs` file changes it
- [ ] The root `CLAUDE.md` (Commands, pre-commit and Formatting sections) and `crates/CLAUDE.md` describe the treefmt setup, and no longer mention the `nixfmt` / `rust-fmt` checks or the per-formatter hook

## Constraints

- `treefmt-nix` follows this flake's `nixpkgs`, so `flake.lock` gains no second nixpkgs
- Each platform's formatter config is evaluated against that platform's own pkgs (the Darwin and Linux nixpkgs inputs stay separate)
- `lib.mkShells` / its base shell packages and the project templates are unchanged; downstream shells keep bare `nixfmt`
- No flake-parts
