---
# dotfiles-rhvw
title: Revisit beans frontend pnpm/node pins after Tahoe upgrade
status: completed
type: task
priority: low
created_at: 2026-06-01T21:27:39Z
updated_at: 2026-06-06T16:49:42Z
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
- [x] pnpm pin is *replaced* by a workaround (not dropped), so the comment
      stays — rewritten to explain the trackUnmanagedFds patch. nodejs pin
      already gone.

## References

- nixpkgs#525627 — pnpm 11 fd-management SIGKILL on darwin (open)
- nixpkgs#522703 — fetcherVersion 4 (pnpm 11 SQLite store determinism)
- Fixed in commit cf8bdb6 (pnpm_9 + nodejs_22)

## Update 2026-06-01

Dropped the nodejs_22 pin — packages/beans/default.nix now uses the default node 24. `nix build .#beans` builds the frontend cleanly (no libuv kqueue EINTR abort) and `nix flake check` passes. The Tahoe upgrade resolved it.

Remaining tasks (pnpm_9 → pnpm_11 + fetcherVersion 4, update.sh sync, dropping the pnpm comments) stay open at low priority, still blocked on nixpkgs#525627.

- 2026-06-01 (post-Tahoe): re-tested plain `pnpm` (11.4.0) + `fetcherVersion = 4` via an isolated `fetchDeps` build. Still SIGKILLs (`Killed: 9`, exit 137) during `pnpm install`. Tahoe did **not** fix nixpkgs#525627 — it is an upstream darwin fetcher bug, not kernel-related. `pnpm_9` pin retained; remaining pnpm tasks stay blocked on upstream.

## Update 2026-06-06 — pnpm_9 → patched pnpm_11 (nixpkgs#525627 workaround)

Applied the workaround from nixpkgs#525627 comment 4635647418: override
`pnpm_11` to 11.5.2 and patch `dist/pnpm.mjs` to construct the worker pool
with `trackUnmanagedFds: false`. Now in `packages/beans/default.nix` and
`update.sh`.

**Gotcha found:** the comment's literal snippet uses `fetchPnpmDeps { inherit pnpm; }`.
Using `pnpm.fetchDeps` / `pnpm.configHook` (the passthru attrs) does NOT work —
they hard-reference `buildPackages.pnpm_11` and ignore `overrideAttrs`, so the
patch never reaches the fetch/build (verified: build log showed `pnpm/11.4.0`
and the unmanaged-fd warnings). Switched to the top-level `fetchPnpmDeps` and
`pnpmConfigHook` with the patched pnpm passed explicitly. Also dropped the
`packages: []` pnpm-workspace.yaml hack — pnpm 11 doesn't need it.

**Result:**
- Fetch SIGKILL: **fixed**. `pnpmDeps` builds reliably; new
  `pnpmDepsHash = sha256-VAy1djjC7h3Swp5R8KgUeMMexLEPmrk6vvi3X6aKeTU=`.
- `nix build .#beans` produces working `beans` + `beans-serve` binaries.

**Important correction to the 2026-06-01 note:** the libuv `kqueue.c` EINTR
abort (`Abort trap: 6`) was NOT fixed by Tahoe — that was a lucky single run.
Forcing 6 clean frontend rebuilds: **~2/6 (≈33%) hit the kqueue abort** at node
teardown, *after* the frontend output is fully written. Critically, the
committed **pnpm_9 baseline aborts at the same ~2/6 rate** — so the kqueue
flakiness is a pre-existing, pnpm-version-independent node-24-on-darwin bug,
NOT a regression from this migration. The frontend bundle is also
non-deterministic across rebuilds (output differs), again on both pnpm versions.

Net: migrating to patched pnpm_11 is a clean win on the fetch side and removes
the pnpm_9 pin + workspace hack, with no new build flakiness. The ~33% kqueue
abort remains a separate, orthogonal CI-reliability problem worth its own bean.

## Summary of Changes

Migrated the beans frontend off the `pnpm_9` pin to a patched `pnpm_11`
(11.5.2 with `trackUnmanagedFds: false`, per nixpkgs#525627 comment), wired
through the top-level `fetchPnpmDeps`/`pnpmConfigHook` so the override actually
applies. Dropped the `packages: []` workspace hack, regenerated `pnpmDepsHash`,
and synced `update.sh`. Fetch SIGKILL resolved; `nix build .#beans` works.

Deliberately *not* addressed here: the pre-existing ~33% flaky libuv `kqueue.c`
EINTR abort during the frontend build. It is pnpm-version-independent (the old
pnpm_9 path aborts at the same rate) and orthogonal to this migration. Left
documented in this bean only, no separate follow-up, per decision on 2026-06-06.
