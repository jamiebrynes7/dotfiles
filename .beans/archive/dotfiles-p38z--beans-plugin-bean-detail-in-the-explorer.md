---
# dotfiles-p38z
title: 'beans plugin: bean detail in the Explorer'
status: completed
type: task
priority: normal
created_at: 2026-11-05T14:15:53Z
updated_at: 2026-11-06T15:02:24Z
parent: dotfiles-oweh
blocked_by:
    - dotfiles-khut
---

**Spec:** `docs/specs/2026-11-05-paseo-beans-plugin.md` — Server half (RPC contracts: bean; Board and detail queries); Client half (Shared store and selection; Detail panel)

## What to build

Pressing a card on the board selects that bean for the workspace and reveals a "Bean" panel in the Explorer showing its detail; relationship rows in the panel navigate the selection. The panel stays current using the same fingerprint polling as the board.

## Acceptance criteria

- [x] Pressing a card reveals the Explorer with the "Bean" panel showing that bean's title, id, status, type, priority, timestamps and rendered markdown body
- [x] Parent, blockers and children are listed as rows; pressing one shows that bean in the panel
- [x] With nothing selected the panel shows a hint to pick a card; selection is per workspace (selecting in one workspace does not change another's panel)
- [x] Editing the selected bean via the CLI updates the panel within ~10 s
- [x] A selected bean that is deleted shows "Bean <id> not found"
- [x] The detail panel is offered only in the Explorer location, not as a workspace tab

## Summary of Changes

- **Server:** a new `beans.bean` RPC (`{ workspaceId, beanId }`) runs one `beans graphql` query with the id passed as a `-v` variable. The id goes through a Zod fence (`[A-Za-z0-9_.-]+`).
  - It returns `{ kind: "none" } | { kind: "project", fingerprint, bean: BeanDetail | null }`: the fingerprint it read against, in the same shape as `board`. This differs from the spec's bare `BeanDetail | null`.
  - `readBoard` and `readBean` share a `readProject` preamble, which takes the fingerprint before the query and treats a missing data dir as empty.
- **Client:**
  - **Polling:** `use-board.ts` became a generic `usePolled` (fingerprint poll, backoff after a failed load, foreground-only), with `useBoard` and `useBean` on top of it.
  - **Selection store:** a module-level `useSyncExternalStore` store keyed by workspace. Pressing a card selects it and calls `openPanel("beans-detail", { location: "explorer" })`, and the selected card gets an accent border.
  - **Detail panel:** registered with `locations: ["explorer"]` only. It shows the title, type badge, status (noting an inherited one), priority and tags; then parent, blocker and child rows with type icons, which navigate the selection; then the Markdown body. A muted footer holds the id and relative timestamps. With nothing selected it shows a hint, and a deleted bean shows "Bean <id> not found".
  - **Shared badges:** the type badge, priority icon and tag pills now live in `client/badges.tsx`.
- **Fixes from review:**
  - `error ? … : null` banners in both panels, since an empty string would crash React Native.
  - The `Selected` view is keyed by bean, so it never flashes the previous one.
  - The RPC ref is assigned in a layout effect.
  - The first load goes through the fingerprint, so a failure there isn't retried every tick.
- **Verification:**
  - `nix flake check` targets, with 29 node:test cases.
  - Manual: tried on a demo daemon and approved by the user.
