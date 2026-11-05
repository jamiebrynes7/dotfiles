# A beans paseo plugin — spec

Date: 2026-11-05

A repo-local paseo plugin, `beans`, that shows a workspace's beans as a Kanban board in a
workspace tab, shows a selected bean's detail in an Explorer panel, and starts an agent on
a ready bean. All bean data comes from the `beans graphql` CLI, run by the plugin's server
half in the workspace's directory.

## Goals

- In any workspace, open a board of that checkout's beans: status columns and epic lanes.
- Click a card and read the bean in the Explorer, including its rendered body, metadata
  and relationships, without losing the board.
- Start an agent on a ready bean, either in the current workspace or in a new worktree.
  You can edit the prompt, choose the location and choose the provider/model before it
  starts.
- See the board change within ~10 s of an agent editing a bean, without a spawned process
  every tick for every mounted panel.
- In a workspace with no beans project, initialise one with a button.

## Non-goals

- **No editing of beans** from the UI (status, priority, todos, creation). Agents and the
  CLI already do this.
- **No composer attachment source** for beans.
- **No global, cross-project screen.** The board is per workspace.
- **No plugin settings screen.** The plugin has nothing beyond enable/disable.
- **No wiring in this repo's home configuration.** As with the other plugins, hosts enable
  `dotfiles.programs.paseo.plugins.beans` in their downstream system repos.
- **No compact or mobile layout.** The detail panel assumes the Explorer exists.
- No test runner for `ts/` (an existing gap, not this spec's to close).

## Facts this design depends on

Verified against `getpaseo/paseo` at v0.15.1, the pinned tag (`P/` = `packages/plugin/src/`),
and against the `beans` CLI as packaged in `packages/beans`.

1. **Panels.** `addWorkspacePanel({ id, title, icon, locations?, Component })` renders
   arbitrary React Native. `locations` defaults to the workspace (a main tab). `"explorer"`
   makes it an Explorer tab (`P/client/contracts.ts:101,185,210-228`). Panel props carry
   `workspaceId`, `tab`, `theme`, `layout` and an optional `navigation.{openAgent,
   openWorkspace}` (`:36-51,122-149`). `navigation` is undefined on older hosts.
2. **Opening panels.** `client.openPanel(id, { workspaceId, location })` with
   `location: "explorer"` reveals the Explorer sidebar and places the panel there. Omitting
   `location` picks the workspace tab when the panel supports it
   (`app/plugins/workspace-panels/locations.ts:24-34`, `app/plugins/navigation.ts:14-38`).
3. **One module scope.** A plugin installation's client bundle is evaluated once, so all of
   its contributions share module-level state (`app/plugins/evaluate.ts:534-542`). Each host
   (`serverId`) gets its own instance. A reload or reconnect reinstalls the plugin and
   resets that state.
4. **No visibility signal.** A panel cannot tell whether it is the visible tab. Each pane
   keeps up to 3 recent tabs mounted but hidden
   (`app/screens/workspace/workspace-panel-host.tsx:28,110-115`). `react-native`'s
   `AppState` (host-supplied) reports only app foreground and background.
5. **Creating agents.** `paseo.workspaces.ref(id).agents.create({ config: { provider:
   "provider/model", modeId?, thinkingOptionId? }, prompt, title? })` creates an agent in an
   existing workspace. `paseo.workspaces.create({ source: { kind: "worktree", projectId |
   cwd, action: "branch-off", branchName, worktreeSlug? }, agent: {...} })` creates a
   worktree workspace together with its first agent (`packages/client/src/index.ts:153-162,
   186,249-273`, `protocol/messages.ts:2709-2752`). `config.provider` is required and must
   name both a provider and a model. `agents.create` returns an agent handle with its id.
   `workspaces.create` returns a `PaseoWorkspaceHandle`, which carries no agent id
   (`index.ts:179-200`). `workspaces.ref(id).refresh()` returns the workspace with its
   `workspaceDirectory` (`index.ts:846-866`). The server half uses this to resolve a
   directory.
6. **No default provider/model API.** The new-agent form's choice lives in app-local
   storage. Agent list entries carry `provider`, `model`, `currentModeId`,
   `thinkingOptionId`, `workspaceId` and `createdAt`. The list can be sorted by `created_at`
   but not filtered by workspace (`messages.ts:863-880,958-968,1297-1304`).
   `paseo.providers.listAvailable()` / `listModels(provider)` report models with
   `isDefault`.
7. **RPC.** `defineRpc` contracts are Zod-validated on both sides, and a request times out
   after 30 s (`server/plugins/runtime.ts:41`). The server half is a Node subprocess with
   process access, running on the daemon's `PATH`.
8. **beans CLI.** `beans graphql --json '<query>'` finds its project by searching upward
   from the working directory for `.beans.yml`, whose `beans.path` names the data
   directory. It has no subscriptions. `BeanFilter.isBlocked` covers both explicit blockers
   and implicit ones (a blocked ancestor). `Bean.implicitStatus` is a terminal status
   inherited from an ancestor. `beans init` creates `.beans/` and `.beans.yml` in the
   working directory, deriving the defaults itself.
9. **`beans` is on the daemon's PATH.** `home/programs/beans.nix` installs it through
   `home.packages`, and the paseo module's `servicePath` includes the profile `bin`
   directories.

## Architecture

The plugin follows the existing repo-local layout. `ts/paseo-plugin-beans/` holds
`index.client.tsx`, `index.server.ts`, `client/`, `server/` and `shared/`, and the
manifest declares `id: "beans"` with a `requirements.paseo` lower bound of the version it
is built against. `packages/paseo-plugin-beans/default.nix` is a one-liner over
`buildPaseoPlugin`.

```
client (one module scope per host)                server (Node subprocess)
┌──────────────────────────────────┐   RPC        ┌───────────────────────────────┐
│ Board panel (workspace tab)      │─────────────▶│ fingerprint(workspaceId)      │
│ Detail panel (explorer)          │              │ board(workspaceId)            │
│ shared store: selection, cache   │              │ bean(workspaceId, beanId)     │
│ header button, command item      │              │ init(workspaceId)             │
│ Start modal ──▶ client.paseo     │              │   └─ spawn `beans` in the     │
└──────────────────────────────────┘              │      workspace directory      │
                                                  └───────────────────────────────┘
```

Every RPC takes a `workspaceId`, never a path. The server resolves the directory through
`paseo.workspaces.ref(id).refresh()`; an unknown workspace or a null directory is an RPC
error. This way a client cannot point the CLI at an arbitrary directory. The beans
project is the one the CLI would find from the workspace's `directory`. A worktree
therefore shows its own branch's beans, including those an agent has created or edited
there.

Creating agents and workspaces happens client-side through `client.paseo`, because the
client owns the navigation that follows.

## Server half

### RPC contracts (`shared/`)

| RPC | Input | Output |
| --- | --- | --- |
| `beans.fingerprint` | `{ workspaceId }` | `{ kind: "none" }` \| `{ kind: "project", fingerprint: string }` |
| `beans.board` | `{ workspaceId }` | `{ kind: "none" }` \| `{ kind: "project", fingerprint, beans: BoardBean[] }` |
| `beans.bean` | `{ workspaceId, beanId }` | `BeanDetail \| null` |
| `beans.init` | `{ workspaceId }` | `{ ok: true }` |

`BoardBean` holds `id`, `slug`, `title`, `status`, `implicitStatus`, `type`, `priority`,
`parentId` and `blocked: boolean`. `BeanDetail` adds `body`, `createdAt`, `updatedAt`, the
parent `{ id, title, status }`, `blockedBy[]` and `children[]` as `{ id, title, status }`.
Queries are fixed strings, and values reach them only through `beans graphql -v` JSON
variables, never by splicing them into the query text. Zod also limits bean ids to
`[A-Za-z0-9-]+`.

### Fingerprint (the cheap check)

`fingerprint` spawns no process. It walks up from the workspace directory to the nearest
`.beans.yml`. If there is none, the result is `none`. Otherwise it reads `beans.path` and
stats every file in the data directory, recursively, so `archive/` counts too. It returns
a hash of `.beans.yml`'s mtime plus each file's relative path, size and mtime. A file
added, removed, edited or archived changes the hash. Any directory read error is reported
as an RPC error, not as `none`.

### Board and detail queries

`board` runs a single `beans graphql --json` call that fetches every bean's `BoardBean`
fields, plus an aliased `blocked: beans(filter: { isBlocked: true }) { id }` to compute
`blocked`. It returns the fingerprint computed just before the spawn, so a change during
the query triggers another refetch on the next tick rather than being lost. `bean` fetches
a single bean with its relationships.

The server does not cache. The client's fingerprint comparison is the cache.

### Init

`init` refuses (with an RPC error) when a `.beans.yml` is already found from the
directory. Otherwise it runs `beans init` with no flags in the workspace directory. The
resulting files are left uncommitted.

### Process handling

Every spawn uses `node:child_process` with argv (no shell), the workspace directory as
`cwd`, and a 20 s kill timer, which stays inside the 30 s RPC limit. A non-zero exit, a
timeout, `ENOENT` for `beans`, or unparseable output becomes an RPC error carrying stderr's
tail. GraphQL `errors` in otherwise valid output are errors too.

## Client half

### Board panel

The board is registered as a workspace-location panel (`id: "beans-board"`, title "Beans").
You open it in two ways:

- **A per-workspace header button.** It is kept in step with a
  `paseo.workspaces.list({ subscribe: {} })` subscription, as the direnv plugin does.
- **A Command Center item** with `context: "workspace"`, which calls `openPanel`.

**Polling.** While mounted and while `AppState` is `active`, the panel calls `fingerprint`
every 10 s. It calls `board` on mount, and again whenever the fingerprint differs from the
last one loaded. It stops on unmount and resumes immediately when the app returns to the
foreground. Hidden but mounted tabs keep polling, which is cheap because a fingerprint is
only file stats. A refresh button forces `board`.

**Layout.** The board lays its lanes out in a vertical scroll, and each lane is a
horizontal row of columns.

- **Columns:** `draft`, `todo`, `in-progress` and `completed`. `scrapped` is hidden behind
  a "Show scrapped" toggle, held in tab state. A card's column is its `implicitStatus` when
  set, otherwise its `status`. A todo task under a completed epic therefore files as
  completed, which matches the CLI's own ready logic.
- **Lanes:** one per epic, keyed by each card's nearest epic ancestor, which is found by
  walking `parentId` through the board data. There is also a final "No epic" lane.
  - A lane whose epic is completed or scrapped is collapsed by default, and that
    collapse state is held in tab state.
  - A lane with no cards in the visible columns is omitted.
  - Lanes are ordered by epic priority, then title.
- **Cards:** every bean whose type is not `epic` or `milestone`, ordered within a cell by
  priority, then `updatedAt` descending. A card shows the id, title, type, priority (if not
  normal) and a blocked marker. Pressing a card selects it (see below).

**States.**

- Loading shows the host `Loading`.
- `none` shows "No beans project in `<directory>`" with an **Initialise beans** button. On
  success the button refetches. On error it shows a toast.
- An RPC error keeps showing the last loaded board, if there is one, under an error banner
  with a retry action. Polling continues.

### Shared store and selection

A module-level store, keyed by `workspaceId`, holds the selected bean id. Both panels
subscribe to it. Pressing a card sets the selection and calls
`client.openPanel("beans-detail", { workspaceId, location: "explorer" })`. A reinstall
resets the store, and the detail panel then shows its empty state.

### Detail panel

The detail panel is registered with `locations: ["explorer"]` only (`id: "beans-detail"`,
title "Bean").

- **With no selection:** a hint to pick a card on the board.
- **With a selection:** it calls `bean` and re-fetches when its own `fingerprint` poll
  changes, using the same 10 s / `AppState` rule. It renders:
  - the title, id, status, type, priority and timestamps;
  - the body, through the host's `Markdown`;
  - the parent, blockers and children as rows. Pressing one sets the selection to that
    bean.

  A bean that no longer exists (`null`) shows "Bean `<id>` not found" and leaves the
  selection in place.
- **A Start button,** shown only when the bean is ready, meaning all of:
  - it is not blocked;
  - its `status` is `todo` or `in-progress`;
  - it has no `implicitStatus`;
  - its type is not `epic` or `milestone`.

  Pressing it opens the Start modal.

### Start modal

The Start modal is a host `Modal` with these fields:

- **Prompt.** A multi-line `TextInput`, prefilled with `Implement bean <id>.` In repos that
  ship the task-implementer skill, this triggers the skill. Elsewhere the agent reads the
  bean through the CLI.
- **Where.** Either "This workspace" or "New worktree". "New worktree" reveals a branch
  field, prefilled with `<type>/<slug>` (task-implementer's own branch convention), and
  sends `worktreeSlug` set to the slug. The base is left to the daemon's default.
- **Provider and model.** Choices come from `providers.listAvailable()` and
  `listModels()`. The default is the provider, model, mode and thinking option of:
  1. the most recently created agent in this workspace; failing that,
  2. the most recently created agent in this workspace's project; failing that,
  3. `claude` with its `isDefault` model.

  Both agent lookups use one `agents.list` sorted by `created_at` descending and filtered
  on the client. Mode and thinking are carried over only when the chosen provider still
  matches the defaulted one.

**Submit.**

- **This workspace:** `workspaces.ref(workspaceId).agents.create({ config, prompt, title })`.
- **New worktree:** `workspaces.create({ source: { kind: "worktree", projectId, action:
  "branch-off", branchName, worktreeSlug }, agent: { config, prompt, title } })`.

`title` is `<id>: <bean title>`. On success the modal closes and the client navigates. For
this workspace it calls `navigation.openAgent` with the new agent's id. For a new worktree
it calls `navigation.openWorkspace` with the new workspace's id, because the handle carries
no agent id and the worktree's only agent is the one just created. If `navigation` is
undefined, it shows a toast naming the agent instead. On failure the modal stays open with the error, and nothing is retried
automatically.

## Error handling summary

| Failure | Result |
| --- | --- |
| No `.beans.yml` from the workspace directory | Empty state with an Initialise button |
| `beans` missing from PATH, a spawn timeout, a non-zero exit, bad JSON, GraphQL errors | RPC error, shown in a banner over the last good board, with retry |
| Data directory unreadable | `fingerprint` RPC error, handled the same way |
| `init` when a project already exists, or `beans init` fails | Toast; the board refetches |
| Selected bean deleted | "Bean not found" in the detail panel |
| Agent or workspace creation fails (bad provider, branch exists, …) | Error inline in the Start modal, which stays open |
| Host without `navigation` | Toast instead of navigating |
| Plugin reinstalled (reload or reconnect) | Selection cleared; panels refetch on remount |

## Testing seams

- **Existing checks:** `paseo-plugin-beans-typecheck` and `paseo-plugin-beans-sdk-version`
  (from `ts/default.nix`), and `paseo-plugin-requirements` against the manifest. The
  package build runs as part of `nix flake check`.
- **Manual, on one host with the plugin enabled:**
  - **This repo:** the board shows epics as lanes; a card opens the Explorer detail; an
    agent changing a bean's status moves its card within ~10 s; the scrapped toggle works.
  - **Start in this workspace:** the prompt can be edited, the model defaults to the
    workspace's latest agent's, and the client navigates to the new agent.
  - **Start in a new worktree:** the branch is `<type>/<slug>`, the new workspace appears,
    and its board shows the worktree's beans.
  - **A repo with no `.beans.yml`:** the empty state appears; Initialise creates the project
    and the board loads.
  - **Blocked, draft and epic beans** show no Start button.
