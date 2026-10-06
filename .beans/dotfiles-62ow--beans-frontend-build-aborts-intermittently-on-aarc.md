---
# dotfiles-62ow
title: beans-frontend build aborts intermittently on aarch64-darwin
status: in-progress
type: bug
priority: normal
created_at: 2026-10-06T16:03:44Z
updated_at: 2026-10-06T16:09:49Z
blocking:
    - dotfiles-rwwd
---

`packages/beans` fails to build on aarch64-darwin roughly 1 in 3 times: `pnpm build` in the
`beans-frontend` derivation finishes writing the site (`✔ done`), then node aborts at exit
(`Abort trap: 6`), preceded by repeated `File descriptor N opened in unmanaged mode twice` warnings.

Reproduced 2/2 on the new macos-latest CI leg (PR #359) and 1/3 with local
`nix build --rebuild` on an M-series Mac. It went unnoticed because CI never built
`checks.aarch64-darwin` before #359, and local builds reuse a stored output.

Same family as nixpkgs#525627, which `packages/beans/default.nix` already works around for the
pnpm *fetch* by patching pnpm's WorkerPool to `trackUnmanagedFds: false`. That patch does not
reach the worker threads spawned during `pnpm build`.

## Todo

- [x] Identify which process/worker emits the fd warnings and aborts during `pnpm build`
- [x] Fix in `packages/beans/default.nix` (and mirror in `update.sh` if the pnpm expression changes)
- [x] Verify: repeated `nix build --rebuild` of beans-frontend passes on aarch64-darwin (8/8, zero fd warnings; was 1-in-3 crashing)
- [ ] Verify: macos-latest leg green on the fix PR, then rerun #359

## Root cause

The aborting process is the `vite build` child (pnpm only re-raises its SIGABRT). SvelteKit 2.54's
`forked()` (`@sveltejs/kit/src/utils/fork.js:38`) runs post-build analysis and prerendering in a
`new Worker(...)` with default options, so `trackUnmanagedFds` is on; worker teardown closes fds
libuv has since recycled, and node aborts. Same mechanism as nixpkgs#525627.

Fix: a `preBuild` `substituteInPlace --replace-fail` adds `trackUnmanagedFds: false` to that
Worker. It is a build-phase patch, so `pnpmDepsHash` and `update.sh`'s mirrored fetch expression
are unaffected.
