---
# dotfiles-khut
title: 'beans plugin: read-only Kanban board in a workspace tab'
status: completed
type: task
priority: normal
created_at: 2026-11-05T14:15:53Z
updated_at: 2026-11-06T14:45:08Z
parent: dotfiles-oweh
---

**Spec:** `docs/specs/2026-11-05-paseo-beans-plugin.md` — Architecture; Server half (RPC contracts: fingerprint, board; Fingerprint; Board and detail queries; Process handling); Client half (Board panel)

## What to build

A new repo-local paseo plugin, `beans`, packaged for hosts to enable. In any workspace, a header button and a workspace-context Command Center item open a "Beans" tab. The tab shows the beans of the project the CLI would find from the workspace's directory as a board: status columns, one lane per epic plus "No epic", and cards for the non-container beans. The board stays current by polling the cheap fingerprint check and refetching only when it changes.

## Acceptance criteria

- [x] `nix flake check` builds the plugin package and runs its typecheck, SDK-version and plugin-requirements checks green
- [x] With the plugin enabled on a host, each workspace has a header button and a Command Center item that open the "Beans" workspace tab
- [x] In this repo the board shows columns draft / todo / in-progress / completed, a lane per epic (nearest epic ancestor) plus "No epic", and cards showing id, title, type, non-normal priority and a blocked marker for blocked beans
- [x] A card under a completed or scrapped ancestor files in that ancestor's terminal column (implicitStatus wins)
- [x] Scrapped beans appear only with the "Show scrapped" toggle on; lanes of completed/scrapped epics start collapsed; lanes with no visible cards are omitted
- [x] A bean status change made via the CLI moves its card within ~10 s while the tab is mounted, without a manual refresh; a refresh button forces an immediate refetch
- [x] The poll issues only fingerprint requests when nothing has changed (no `beans` process spawned per tick), and pauses while the app is backgrounded
- [x] An RPC failure (e.g. `beans` not on PATH, bad output) shows an error banner with retry over the last loaded board instead of blanking it
- [x] RPCs accept a `workspaceId` only; an unknown workspace is an RPC error

## Notes

The "no beans project" result may render a plain placeholder in this ticket; the Initialise flow is a separate ticket.

## Summary of Changes

New repo-local paseo plugin `beans` (`ts/paseo-plugin-beans/`, packaged as `packages/paseo-plugin-beans`).

- **Server:** `beans.fingerprint` and `beans.board` RPCs take only a `workspaceId` and resolve the directory through `workspaces.ref(id).refresh()`; an unknown workspace is an RPC error.
  - The fingerprint uses stats only: it searches upward for `.beans.yml` and hashes path, size, inode, mtime and ctime over the data dir, archive included.
  - The board is one `beans graphql --json` call with an aliased `isBlocked` query. It runs argv-only with a 20 s kill timer, and a non-zero exit, a timeout, ENOENT, bad JSON and GraphQL errors each become an error carrying stderr's tail.
  - A project whose data directory is missing returns an empty board, since the CLI refuses it.
- **Client:**
  - Opening: a `beans-board` workspace panel, a workspace Command Center item, and a header button for each workspace (driven by a workspace-list subscription, as in direnv).
  - Polling: a 10 s fingerprint poll that pauses in the background, refetches the board only when the fingerprint changes, and doesn't retry a failing board until the fingerprint moves. A refresh button forces a refetch, and an error banner with Retry shows over the last good board.
- **Layout** (`shared/layout.ts`):
  - Status columns, with implicitStatus winning and scrapped behind a toggle.
  - One lane per epic (nearest epic ancestor) plus No epic. Empty lanes are omitted, and completed or scrapped epics start collapsed.
  - Cards show title, a type badge, a priority icon, a blocked marker, tags and the id.
- **Changed from the spec, at review:**
  - Lanes are grouped by the epic's own status (in progress, todo, draft, completed, scrapped) before priority and title.
  - Columns flex to fill the width.
  - `BoardBean` gained `updatedAt` and `tags`, and `none` carries the directory.
- **Verification:**
  - `nix flake check`: package, typecheck, sdk-version and requirements, plus 25 node:test cases.
  - Manual: a demo daemon with a dummy project, reviewed by the user.
  - The poll and error-banner paths were covered by code review and server tests, not by hand. Follow-up dotfiles-wdsw adds tests for the client poll.
