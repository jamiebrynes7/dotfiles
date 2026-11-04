---
# dotfiles-wdd4
title: Restore macOS CI once a build cache is available
status: draft
type: feature
created_at: 2026-10-06T18:00:41Z
updated_at: 2026-10-06T18:00:41Z
---

Land the `macos-latest` CI leg that was split out of #359, once CI has a binary cache.

`ci.yml` is `ubuntu-latest` only, so `checks.aarch64-darwin` is never built in CI. Lock-bump PRs
from `update-flake-lock.yml` therefore auto-merge with a `nixpkgs-darwin` move validated by nothing
until a Mac next runs `just update`. The leg is ready on its own PR: a `flake` matrix over
ubuntu-latest + macos-latest behind a thin `flake-check` aggregate gate. Branch protection requires
exactly that context name; matrixing the job in place would stall every PR.

It was parked on cost. Uncached on #359, macOS took **20 min** against 11 min for Linux, and the legs
run in parallel, so macOS sets the total. The time goes into building Rust crates, paseo
(`npm ci` + native `node-pty`) and the beans frontend from scratch on every run.

Running it was still worth it: it surfaced an intermittent aarch64-darwin crash in beans-frontend
(dotfiles-62ow, fixed in #360).

## Todo

- [ ] Choose and wire up a push cache for CI (e.g. `DeterminateSystems/flakehub-cache-action` or `cachix/cachix-action`)
- [ ] Rebase the macOS CI PR onto it, and re-measure both legs warm
- [ ] Update the `update-flake-lock.yml` job comment, which says Darwin lands unvalidated
- [ ] Land it
