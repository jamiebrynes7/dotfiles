---
# dotfiles-aubb
title: Include nixfmt on `nix flake check`
status: completed
type: task
priority: normal
created_at: 2026-06-06T20:11:28Z
updated_at: 2026-07-04T20:42:09Z
---

We've included Rust format/lint/test in `nix flake check`, we should do the same for `nixfmt` runs

## Summary of Changes

Added a `nixfmt` flake check so `nix flake check` (and thus CI) gates Nix
formatting, mirroring the existing Rust `rust-fmt` check.

- `flake.nix`: new `mkNixfmtCheck` helper builds a `runCommandLocal` derivation
  that runs `nixfmt --check` over the repo's `.nix` files. Source is a
  `fileFilter`/`toSource` fileset of the git-filtered flake tree, so vendored
  `.direnv` third-party Nix is excluded and the check only re-runs when `.nix`
  files change. Wired into `checks.<system>` as `nixfmt` for both
  aarch64-darwin and x86_64-linux. Uses `find … -exec nixfmt --check {} +`
  (nixfmt 1.2.0 deprecates directory args; also avoids a vacuous stdin pass on
  an empty set).
- `CLAUDE.md`: note that `nix flake check` also checks Nix formatting; bump
  freshness date.

Verified: clean tree passes the check (exit 0); a staged misformatted `.nix`
file fails it (exit 1, "not formatted").
