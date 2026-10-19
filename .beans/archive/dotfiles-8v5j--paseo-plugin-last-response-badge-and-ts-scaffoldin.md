---
# dotfiles-8v5j
title: 'paseo plugin: last-response badge (and ts/ scaffolding)'
status: completed
type: feature
priority: normal
created_at: 2026-10-18T12:09:55Z
updated_at: 2026-10-18T13:34:44Z
---

A repo-local paseo plugin that shows how long ago an agent last responded, as a composer pill under each agent's message box: "Responding…" while a turn runs, then "Just now" / "1 minute ago" / "1 hour 5 minutes ago". It is the first repo-local plugin, so it also builds the `ts/` scaffolding designed in `docs/specs/2026-09-21-paseo-plugins.md` ("Repo-local plugins: `ts/`", phase 2). That scaffolding was previously tracked in dotfiles-vxsd.

## Research (paseo v0.11.4)

- **Surface:** `client.addComposerPill({ id, workspaceId, agentId, button })` puts a pill in one agent's composer track, next to Tasks/Subagents. It always renders an icon (required, e.g. `Clock`) plus `label`. The label is a static string, so one shared interval (~30s) calls `pill.update({ label })`. A pill is a button, so it needs a `behavior`: a no-op action, or a popover with the absolute time.
- **One pill per agent:** follow `plugin-examples/local-plugin/client/main.tsx`, which subscribes with `client.paseo.agents.list({ subscribe: {}, signal })`, re-registers pills on each snapshot, and aborts on entry cleanup.
- **Timestamp source:** do NOT use `PluginAgentSnapshot.lastActivityAt`. It is the agent's `updatedAt` (`packages/app/src/utils/agent-snapshots.ts:116`), which `touchUpdatedAt` bumps on mode, title, archive and other changes. Use timeline entries instead, which carry `timestamp`. Take the newest assistant-message entry from `paseo.agents.ref(id).timeline.refetch({ direction: "tail", limit })`. **Constraint found in review:** the daemon's timeline fetch runs `ensureAgentLoaded`, which resumes a stored agent's provider session, so the plugin must never fetch for an agent the daemon hasn't loaded. Mounting does not prove an agent is loaded either: the app keeps hidden tabs, split panes and visited workspaces mounted. **Chosen design:** an `index.server.ts` daemon half records the time on `agent.turn_ended` (fires only for live turns, so it wakes nothing) and persists it to `$PASEO_HOME/plugin-state/last-response.json`. The client reads it with one `last-response.list` RPC per directory snapshot (initial load and every reconnect), and stamps `Date.now()` itself on live running→idle transitions. The client never fetches a timeline. Agents whose last turn predates the plugin show no pill until they next respond. While `status === "running"`, show "Responding…" so the count starts when the turn ends, not when the reply starts.
- **Rejected:** timeline renderers (one timestamp per message, not a single badge) and a server-side `agent.turn_ended` hook writing a row with `timeline.append` (it writes into each agent's saved history).
- Directory plugins need no build: the daemon compiles them with esbuild (`write: false`), and `@getpaseo/plugin*` imports are host-supplied.

## Todo

### Scaffolding (`ts/`, per spec)
- [x] `ts/default.nix` overlay fragment in `crates/default.nix`'s slot, imported into `defaultOverlays`, exporting `buildPaseoPlugin { pname; src; }`: a `lib.fileset` plain copy excluding `node_modules`/build output, no npm
- [x] `dotfiles.internal.tsChecks`: per-plugin `typecheck` (`buildNpmPackage` running `tsc --noEmit`, `npmDepsHash` from the committed lockfile) and `sdk-version` (`@getpaseo/plugin` devDependency vs `version` in `packages/paseo/hashes.json`, failing with both values named)
- [x] `flake.nix`: merge `tsChecks` into `checks` next to `rustChecks`; add `pkgs.nodejs` to the devShell
- [x] `packages/paseo-plugin-last-response/default.nix` as a one-liner over `buildPaseoPlugin` (mirrors `packages/beans-daemon`)

### Plugin
- [x] `ts/paseo-plugin-last-response/`: `paseo-plugin.json` (with `requirements.paseo`), `index.client.tsx`, `package.json` + `package-lock.json` (SDK devDependency pinned to the daemon version), `tsconfig.json`
- [x] Agent-list subscription that registers and removes one composer pill per agent
- [x] Last-response timestamp from timeline seed + live subscription; "Responding…" while running
- [x] Daemon half: `agent.turn_ended` recorder, persisted store, `last-response.list` RPC, separate Node-typed tsconfig
- [x] Relative-time formatter ("Just now", "1 minute ago", "1 hour 5 minutes ago", …) on a shared interval, with timers and subscriptions torn down in the entry's cleanup
- [x] Configure it by default in `home/programs/paseo.nix` with `lib.mkDefault`, like `catppuccin-theme`; hosts opt out with `plugins.last-response.enable = false`
- [x] `nix flake check` green, including the existing `paseo-plugin-requirements` check
- [x] Verify on a real host: pill appears, ticks, survives reload and reconnect (deferred to the user after merge, by their call; a scratch 0.11.4 daemon loaded the plugin as `running` pre-merge)
- [x] Update `CLAUDE.md` (Project Structure gains `ts/`; Packages section covers repo-local plugins)

## Summary of Changes

- **`ts/` scaffolding** (`ts/default.nix`, imported as an overlay after `crates/`): `buildPaseoPlugin`, a plain fileset copy with no npm, plus `dotfiles.internal.tsChecks`, merged into `checks` on both systems. For each `ts/paseo-plugin-*` directory it derives `<dir>-typecheck` (`npm run typecheck` via `importNpmLock`, so there is no deps hash) and `<dir>-sdk-version` (the `@getpaseo/plugin` version must equal paseo's pin in `package.json` and in both lockfile records). `nodejs` was added to the devShell.
- **`last-response` plugin** (`ts/paseo-plugin-last-response/`, packaged as `packages/paseo-plugin-last-response`, configured by default with `mkDefault` in `home/programs/paseo.nix`):
  - The client shows a Clock composer pill per agent: "Waiting on you", "Responding…" or "N minutes ago", re-rendered every 30s and hidden until there is a time to show.
  - The daemon half records `Date.now()` on `agent.turn_ended` into `$PASEO_HOME/plugin-state/last-response.json`. It serves those times over `last-response.list`, which also prunes agents that are no longer in the directory.
  - The client syncs once per directory snapshot and stamps live running→idle transitions itself; each sync replaces local stamps, so clock skew can't stick.
  - Client and daemon halves typecheck under separate tsconfigs; client code gets no DOM or Node types, and its few globals are declared by hand.
- **Design change from review:** the original timeline-fetch approach was dropped. A timeline fetch makes the daemon resume a stored agent's provider session, and the client cannot tell which agents are loaded, because hidden tabs and panes stay mounted.
- **Docs:** `CLAUDE.md` covers `ts/`, the bump-time re-pin, the layout rule and the timeline-fetch gotcha.
- **Verified:** `nix flake check` passes on x86_64-linux and the Darwin checks evaluate. Both new checks were shown to fail on bad input. The store was exercised under Node. A scratch 0.11.4 daemon loaded the built plugin as `running`. No real agent turn was driven.
