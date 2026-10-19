# direnv paseo plugin: allow new worktrees of allowed projects — spec

Date: 2026-10-19
**Supersedes:** `2026-10-18-paseo-direnv-plugin.md`, its non-goal "No extension of direnv's
trust" and the goal "the plugin never approves an `.envrc` on its own". Everything else in
that spec stands.

When paseo creates a worktree of a project whose root checkout's `.envrc` is already
allowed, the `direnv` plugin runs `direnv allow` on the new worktree, so agents launched
there (including one fanned out by an orchestrator) get the devshell with no manual step.

## Why

direnv keys approval on the `.envrc`'s absolute path plus its content, so every new
worktree starts blocked. With the original design, every fanned-out workspace (e.g. the
nimbus task-orchestrator's `paseo workspace create --mode branch-off` then `paseo run`)
has its first agent refused until someone runs `direnv allow` there.

Alternatives considered and rejected:

- **direnv `whitelist.prefix` on paseo's worktree root.** Trusts everything under the path,
  including worktrees of projects never allowed, and lives in a store-managed
  `direnv.toml`.
- **`worktree.setup: direnv allow` in each repo's `paseo.json`.** Keeps paseo's fork-PR
  gate, but needs a committed file per repo, and setup runs in the background: it races
  `paseo workspace create` → `paseo run`, and with `paseo run --new-workspace` setup only
  starts after the first agent is created, so that agent is always refused.
- **Gate on the worktree's `HEAD` being on an `origin` branch.** Not needed for the
  trust rule; kept as a possible hardening (see Non-goals).

## Trust rule

A new worktree is allowed when **all** of these hold:

1. It came from a paseo `workspace.created` event (never an agent open, never a directory
   the user made by hand).
2. The workspace directory is under paseo's worktrees root.
3. Its source checkout's own `.envrc` is allowed by direnv right now.
4. The worktree has an `.envrc` at its root.

Allowing the root checkout is the per-project opt-in. A project never allowed, or whose
root `.envrc` was edited and not re-allowed, gets no automatic allows, and its worktrees
behave exactly as in the original spec (refused until allowed).

**Accepted risk.** The rule is an opt-in per project, not a check on the worktree's
content: a worktree may be on any branch, and `use flake .` evaluates that branch's
flake, `shellHook` included. In particular a paseo `checkout-pr` of a fork PR against an
allowed project is allowed too, bypassing paseo's own setup gate for fork PRs (the plugin
cannot see that gate: `untrustedSource` is not in the hook payload or the workspace
descriptor). The mitigation is procedural: don't `checkout-pr` outside contributors' PRs
into paseo worktrees of allowed projects.

## Upstream facts this design depends on

Verified against `getpaseo/paseo` at v0.11.4, plus direnv 2.37.1.

1. **The event.** `server.on("workspace.created", handler)` receives
   `{ workspace: { id, projectId, cwd, name, archivedAt } }`. For worktree workspaces it is
   emitted from `createWorkspaceForWorktree` once the worktree exists and the workspace is
   registered, before any agent is created, including under `paseo run --new-workspace`
   (`workspace-provisioning-service.ts`). It is also emitted for local workspaces, which
   rule 2 filters out.
2. **Ordering.** `PluginRuntime.emit` sends the event over the plugin's IPC channel at
   once; a later `agent.session_open` hook goes over the same channel. The plugin process
   calls handlers synchronously on receipt (`lifecycle/index.ts` `invoke`). So an event
   handler that records its pending work before its first `await` is always visible to a
   later `session_open` hook in the same plugin process.
3. **Worktree layout.** Worktrees live at `<root>/<hash>/<slug>`, where `<root>` is
   `worktrees.root` from `$PASEO_HOME/config.json` (relative paths resolved against
   `PASEO_HOME`), defaulting to `$PASEO_HOME/worktrees`. The daemon's `PASEO_HOME` is in
   the plugin's `process.env` (plugins are forked with the daemon's environment).
4. **Source checkout.** paseo derives a worktree's project from
   `git rev-parse --git-common-dir`, taking its parent when it ends in `.git`
   (`deriveWorktreeProjectHash`). The plugin resolves the source checkout the same way.
5. **direnv's status.** `direnv status --json` run in a directory reports
   `state.foundRC = { path, allowed }`, where `allowed` is 0 (allowed), 1 (not allowed) or
   2 (denied), and `foundRC` is `null` with no `.envrc` in scope. `foundRC.path` may be a
   parent directory's `.envrc`, so the plugin compares it to `<source>/.envrc`.

## Design

A third piece in the plugin's server half, beside the `session_open` hook:

**On `workspace.created`:**

1. Synchronously register a pending entry for `workspace.cwd` (fact 2), then:
2. Skip unless `workspace.cwd` is under the worktrees root (fact 3).
3. Resolve the source checkout (fact 4); skip if it fails.
4. Skip unless `direnv status --json` in the source checkout reports `foundRC.path`
   equal to `<source>/.envrc` and `allowed === 0` (fact 5).
5. Skip unless `<worktree root>/.envrc` exists.
6. Run `direnv allow <worktree root>`.
7. Resolve the pending entry, and drop it.

Every step is best-effort: any failure is logged and leaves the worktree as it was (blocked
unless allowed by hand), which the existing refusal message already explains. Nothing
here throws back to paseo.

**In `agent.session_open`:** before evaluating, await any pending entry whose directory is
`request.cwd` or an ancestor of it (an agent may start in a subdirectory of the workspace),
bounded by the hook's existing time budget. Then evaluate exactly as before.

**Logging** records the decision per workspace (allowed, or which rule skipped it) with
directories only, never `.envrc` content or environment values.

## Non-goals

- No change for existing worktrees, local workspaces, or directories outside paseo's
  worktrees root.
- No warming: a cold devshell is still the timeout refusal plus the header button's Warm
  item.
- No revoking: archiving a worktree leaves a dead allow entry, as `direnv allow` on any
  deleted directory does.
- No `HEAD`-on-`origin` check or other content gate (possible follow-up if fork-PR
  worktrees become a real workflow).
- No configuration; the opt-in is allowing the project's root `.envrc`.

## Testing seams

- The existing `paseo-plugin-direnv-typecheck` and `-sdk-version` flake checks.
- Manual, on a host:
  - `paseo workspace create --isolation worktree --path <allowed repo>` followed at once
    by `paseo run --workspace <id>`: the agent launches with the devshell, no refusal.
  - `paseo run --new-workspace worktree` against the same repo: the first agent launches
    with the devshell.
  - The same against a repo whose root `.envrc` is not allowed: the create is refused as
    blocked, as before.
  - A local (non-worktree) workspace: no allow is attempted.
