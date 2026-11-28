---
# dotfiles-wdd4
title: Restore macOS CI once a build cache is available
status: in-progress
type: feature
priority: normal
created_at: 2026-10-06T18:00:41Z
updated_at: 2026-11-18T16:46:53Z
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

- [x] Choose and wire up a push cache for CI (nimbus via niks3: dotfiles-moh7, #469)
- [x] Rebase the macOS CI PR onto it, and re-measure both legs (cold only: branch runs never push to nimbus)
- [x] Update the `update-flake-lock.yml` job comment, which says Darwin lands unvalidated
- [ ] Land it

## Findings (2026-11-18)

Once rebased, the macOS leg failed in every full run: paseo's Metro web bundle hung at 99.9% or reported `Bundling failed` with no message. The cause was the Metro worker running out of Node heap while Babel-transforming `packages/protocol/dist/generated/validation/ws-outbound.aot.js`, an ~11 MB zod-aot validator that the browser client imports. Node sizes its default heap at ~1/4 of RAM: ~1.75 GB on the 7 GB macos-latest runner, ~4.2 GB on an 18 GB Mac. `--max-old-space-size=1792` reproduces the failure locally. Ruled out along the way: sandboxing (off in both), parallel Nix builds (`max-jobs = 1` still hung), Metro worker count, log volume.

Fix: `packages/paseo` sets `NODE_OPTIONS=--max-old-space-size=4096` for the build. Cold full run with it: macOS 19m51s, Linux 10m03s (paseo's derivation changed, so Linux rebuilt it too). It can go once upstream shrinks the generated validator, keeps it out of the web bundle, or raises the heap in its own build.
