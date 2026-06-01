---
# dotfiles-rhvw
title: Revisit beans frontend pnpm/node pins after Tahoe upgrade
status: in-progress
type: task
priority: low
created_at: 2026-06-01T21:27:39Z
updated_at: 2026-06-01T21:53:03Z
---

Follow-up from the 26.05 bump (dotfiles-dqnt). The beans frontend build in
\`packages/beans/default.nix\` carries two darwin workarounds that should be
re-evaluated once the environment changes:

- \`pnpm_9\` (instead of the 26.05 default pnpm_10/pnpm_11) — pnpm 10/11 SIGKILL
  during \`pnpm install\` on aarch64-darwin. Tracks nixpkgs#525627. Verified on
  2026-06-01 that pnpm_11 + fetcherVersion 4 still reproduces the SIGKILL.
- \`nodejs_22\` (instead of default nodejs_24) — node 24 aborts at libuv kqueue
  teardown (errno == EINTR, kqueue.c) on macOS 14.4.1. Same libuv 1.52.1 across
  node majors, so it's a node-24-on-old-kernel issue, likely fixed by a newer
  macOS.

## Tasks

- [x] After upgrading to macOS Tahoe: drop the \`nodejs_22\` pin (use default node)
      and confirm \`nix build .#beans\` succeeds — no kqueue abort.
- [ ] Re-test \`pnpm_11\` + \`fetcherVersion = 4\` (keep an eye on nixpkgs#525627);
      if the SIGKILL is gone, migrate off pnpm_9 and regenerate pnpmDepsHash.
- [ ] Keep \`packages/beans/update.sh\` in sync with whatever pnpm/fetcherVersion
      the package settles on.
- [ ] If both pins can be dropped, remove the explanatory comments too.

## References

- nixpkgs#525627 — pnpm 11 fd-management SIGKILL on darwin (open)
- nixpkgs#522703 — fetcherVersion 4 (pnpm 11 SQLite store determinism)
- Fixed in commit cf8bdb6 (pnpm_9 + nodejs_22)

## Update 2026-06-01

Dropped the nodejs_22 pin — packages/beans/default.nix now uses the default node 24. `nix build .#beans` builds the frontend cleanly (no libuv kqueue EINTR abort) and `nix flake check` passes. The Tahoe upgrade resolved it.

Remaining tasks (pnpm_9 → pnpm_11 + fetcherVersion 4, update.sh sync, dropping the pnpm comments) stay open at low priority, still blocked on nixpkgs#525627.

- 2026-06-01 (post-Tahoe): re-tested plain `pnpm` (11.4.0) + `fetcherVersion = 4` via an isolated `fetchDeps` build. Still SIGKILLs (`Killed: 9`, exit 137) during `pnpm install`. Tahoe did **not** fix nixpkgs#525627 — it is an upstream darwin fetcher bug, not kernel-related. `pnpm_9` pin retained; remaining pnpm tasks stay blocked on upstream.
