---
# dotfiles-84ro
title: Format and lint the ts/ tree
status: draft
type: task
priority: low
created_at: 2026-09-21T17:32:18Z
updated_at: 2026-09-21T17:32:18Z
parent: dotfiles-vxsd
---

Follow-up from `docs/specs/2026-09-21-paseo-plugins.md`. Deferred with the rest of phase 2: there is nothing to format until the first repo-local plugin exists.

`.githooks/pre-commit` gates `*.nix` with `nixfmt --check` and `*.rs` with `cargo fmt --all --check`, and `nix flake check` is the authoritative version of both (`nixfmt` check in `flake.nix`, `rust-fmt` via crane). TypeScript under `ts/` would need the same two-layer treatment:

- A formatter check in `dotfiles.internal.tsChecks` — prettier over the `ts/` fileset, mirroring `mkNixfmtCheck`'s shape.
- A `*.ts`/`*.tsx` branch in `.githooks/pre-commit`, matching the existing check-only style (reports and blocks, never mutates).
- The formatter binary in the devShell alongside `nodejs`, so a commit from inside the direnv shell can satisfy the hook.

Open question to settle when this is picked up: whether the formatter comes from nixpkgs (pinned with the flake, no lockfile entry) or from the plugin's own devDependencies (matches `templates/projects/typescript`'s npm-script convention, but means the hook depends on `node_modules` being installed).
