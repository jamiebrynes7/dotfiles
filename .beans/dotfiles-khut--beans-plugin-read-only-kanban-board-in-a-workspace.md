---
# dotfiles-khut
title: 'beans plugin: read-only Kanban board in a workspace tab'
status: todo
type: task
priority: normal
created_at: 2026-11-05T14:15:53Z
updated_at: 2026-11-05T14:15:57Z
parent: dotfiles-oweh
---

**Spec:** `docs/specs/2026-11-05-paseo-beans-plugin.md` — Architecture; Server half (RPC contracts: fingerprint, board; Fingerprint; Board and detail queries; Process handling); Client half (Board panel)

## What to build

A new repo-local paseo plugin, `beans`, packaged for hosts to enable. In any workspace, a header button and a workspace-context Command Center item open a "Beans" tab. The tab shows the beans of the project the CLI would find from the workspace's directory as a board: status columns, one lane per epic plus "No epic", and cards for the non-container beans. The board stays current by polling the cheap fingerprint check and refetching only when it changes.

## Acceptance criteria

- [ ] `nix flake check` builds the plugin package and runs its typecheck, SDK-version and plugin-requirements checks green
- [ ] With the plugin enabled on a host, each workspace has a header button and a Command Center item that open the "Beans" workspace tab
- [ ] In this repo the board shows columns draft / todo / in-progress / completed, a lane per epic (nearest epic ancestor) plus "No epic", and cards showing id, title, type, non-normal priority and a blocked marker for blocked beans
- [ ] A card under a completed or scrapped ancestor files in that ancestor's terminal column (implicitStatus wins)
- [ ] Scrapped beans appear only with the "Show scrapped" toggle on; lanes of completed/scrapped epics start collapsed; lanes with no visible cards are omitted
- [ ] A bean status change made via the CLI moves its card within ~10 s while the tab is mounted, without a manual refresh; a refresh button forces an immediate refetch
- [ ] The poll issues only fingerprint requests when nothing has changed (no `beans` process spawned per tick), and pauses while the app is backgrounded
- [ ] An RPC failure (e.g. `beans` not on PATH, bad output) shows an error banner with retry over the last loaded board instead of blanking it
- [ ] RPCs accept a `workspaceId` only; an unknown workspace is an RPC error

## Notes

The "no beans project" result may render a plain placeholder in this ticket; the Initialise flow is a separate ticket.
