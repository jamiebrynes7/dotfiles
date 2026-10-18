# A direnv paseo plugin — spec

Date: 2026-10-18

A repo-local paseo plugin, `direnv`, that launches every agent with the environment direnv
would give a shell in the agent's directory. A workspace header button runs `direnv allow`
and warms direnv's cache in a visible terminal. direnv's own allow list stays the only
trust authority: the plugin never approves an `.envrc` on its own.

Context: [getpaseo/paseo#4621](https://github.com/getpaseo/paseo/discussions/4621). Core
has no per-directory environment feature (three attempts — #1628, #2042, #2954 — closed
unmerged), and the only reply points at a plugin `before("agent.session_open")` hook,
which is what this builds on.

## Goals

- An agent whose directory has an allowed `.envrc` runs with that environment, whether
  it was created, resumed after a daemon restart, refreshed, or imported.
- An agent whose `.envrc` is blocked, fails to evaluate, or is too slow is **not** launched
  with the daemon's environment instead; the launch is refused with an actionable message.
- Trusting an `.envrc` is always a deliberate act through direnv itself.
- One click in the workspace header to run `direnv allow`, and one to warm a slow
  `.envrc` (e.g. a cold nix devshell) outside the hook's time limit.

## Non-goals

- **No extension of direnv's trust.** No inheritance of approval into worktrees, even for
  byte-identical content. direnv keys approval on the `.envrc`'s absolute path plus
  content (verified: an allowed `.envrc` in a checkout is `blocked` in a `git worktree add`
  of the same commit), so every new worktree needs its own `direnv allow`.
- **No in-place environment update** for a running agent. A process's environment is fixed
  at spawn, and the plugin API has no post-launch env hook. Picking up a changed `.envrc`
  is the built-in **Reload agent** action (see "Changed `.envrc`").
- No drift detection or status indicator (follow-up candidate).
- No plugin settings screen; no configuration beyond enable/disable.
- No test runner for `ts/` (separate decision).

## Upstream facts this design depends on

Verified against `getpaseo/paseo` at v0.11.4, the pinned tag.

1. **The hook.** `server.before("agent.session_open", handler)` receives
   `PluginSessionOpenRequest = { agentId; workspaceId: string | null; provider; cwd;
   reason: "create" | "resume" | "refresh" | "import"; purpose: "interactive" | "history";
   env: Record<string, string> }` and a `{ paseo, signal }` context. Returning
   `undefined` leaves the request unchanged. Any field other than `env` changing is
   rejected (`"agent.session_open hooks can only change env"`), and `env` values must be
   strings (`plugins/lifecycle/index.ts`).
2. **Every open runs it.** `AgentManager.buildLaunchContext` calls the hook on create,
   resume, import, and refresh (`agent-manager.ts:5198-5243`). On everything but create,
   `request.env` starts as `{}`. Env overrides are never persisted, so they are recomputed
   on every open.
3. **`request.env` is an overlay, not the environment.** The provider env is the daemon's
   `process.env` with the provider's runtime-settings `env` and then the launch env laid
   over it, in that order
   (`provider-launch-config.ts:218-253`). So the hook can add or override a variable but
   **cannot unset** one, and running direnv with `request.env` as its environment would
   run it with no `PATH` or `HOME`.
4. **The plugin's base environment is the daemon's.** Plugin subprocesses are `fork()`ed
   with no `env` option (`plugins/runtime.ts:233-239`), so the plugin's `process.env` is
   the right base for running `direnv`.
5. **Failure and timeout.** A throwing hook fails the open with
   `Plugin <id> before agent.session_open failed: <message>`. Hooks time out at a fixed
   30 s (`REQUEST_TIMEOUT_MS`, `runtime.ts:42`), aborting `context.signal`, and the
   resulting message is the generic `Plugin RPC timed out: <id>.hook`.
6. **Where a refused create shows up.** The message is shown verbatim, inline, under the
   draft composer, and the draft prompt is restored
   (`app/src/composer/draft/workspace-tab.tsx`), so the user can retry.
7. **direnv's output on a blocked `.envrc`.** `direnv export json` exits 1 and prints
   `error <path>/.envrc is blocked. Run \`direnv allow\` to approve its content` on
   stderr — but **still prints JSON on stdout** holding only `DIRENV_*` bookkeeping
   variables. A non-zero exit must therefore never be parsed as an environment. With no
   `.envrc`, it prints nothing and exits 0. An unset variable appears as `null`.
8. **Workspace header buttons.** `client.addHeaderButton({ id, workspaceId, button })`
   renders in the workspace header; `button.behavior` may be
   `{ kind: "menu", items }`. One registration per workspace, so the client follows
   `paseo.workspaces.list({ subscribe })`. A rejected action shows an error toast.
9. **Workspace terminals.** `paseo.workspaces.ref(id).terminals.create({ command, args,
   name? })` opens a visible terminal whose cwd defaults to the workspace directory
   (worktree directory for worktrees). It needs `workspace.write` — not `daemon.manage`,
   which plugin RPC requires — and has no 30 s limit.
10. **Reload agent.** The workspace tab context menu's **Reload agent** sends
    `refresh_agent_request`, which interrupts any running turn and reopens the session
    from persistence, keeping history — through the hook again with `reason: "refresh"`.
    Plugins cannot trigger it (the plugin `PaseoAgentHandle.refresh()` only refetches a
    snapshot).
11. **No alternative channel.** `paseo.json` scripts are per-repo only (the untracked
    `paseo.json` at this repo's root does not reach new worktrees), and plugins cannot
    contribute scripts or worktree setup steps.

## Architecture

One plugin, `ts/paseo-plugin-direnv/`, id `direnv`, with both halves and no RPC between
them:

- **Server half** — the `agent.session_open` hook. Owns all direnv evaluation.
- **Client half** — a header menu button per workspace with two items that each open a
  terminal. It never talks to the server half.

Packaged as `packages/paseo-plugin-direnv/` (a `buildPaseoPlugin` one-liner), with
`requirements.paseo: ">=0.11.4"`, and registered in `home/programs/paseo.nix` with
`lib.mkDefault`, like `last-response` — on wherever paseo is enabled, off with
`dotfiles.programs.paseo.plugins.direnv.enable = false`.

## Server half: the hook

For each `agent.session_open`:

1. **Skip history opens.** `purpose === "history"` (an archived agent opened to read its
   timeline; its directory may be gone) → return unchanged.
2. **Evaluate.** Run `direnv export json` with `cwd: request.cwd`, the plugin's own
   `process.env` as its environment (fact 4), `context.signal` for cancellation, and its
   own timeout safely under the hook's 30 s — so a slow `.envrc` produces this plugin's
   message rather than the generic one (fact 5).
3. **Classify** (exit status first; stdout is only trusted on exit 0, fact 7):

   | Outcome | Result |
   |---|---|
   | `direnv` not found on the daemon `PATH` | Pass through unchanged; log once per plugin process. The host simply doesn't use direnv. |
   | Exit 0, empty stdout (no `.envrc` in scope) | Pass through unchanged. |
   | Exit 0, JSON | Merge (below). |
   | Non-zero, stderr says `is blocked` | **Refuse**: `.envrc` at `<path>` is blocked by direnv — use the direnv button in the workspace header (Allow), or run `direnv allow` in `<dir>`, then retry. |
   | Non-zero, anything else | **Refuse** with the tail of direnv's stderr (ANSI stripped, trimmed to a few lines) and a pointer to the direnv button's Warm item to see the full output. |
   | Own timeout / aborted | **Refuse**: direnv took longer than `<n>`s in `<dir>` — use the direnv button's Warm item to build its cache, then retry. |

4. **Merge.** Result env = direnv's set variables, then `request.env` laid over them, so an
   explicit per-launch override (from the create request or an earlier plugin) wins over
   the ambient directory environment. The one exception is `PATH`: when both set it, the
   result is `request.env`'s entries first, then direnv's entries not already present,
   so an override keeps priority without dropping the devshell's tools. (A `PATH` in a
   provider's runtime settings is a lower overlay the hook never sees, so direnv's
   `PATH` replaces it; per fact 3 there is no way to merge it from here.) Variables
   direnv reports as `null` (unsets) are
   dropped, so the daemon's value stands (fact 3); an empty string would mean something
   different for many tools. `DIRENV_*` bookkeeping variables are passed through, as a
   shell would have them, so a direnv-hooked shell inside the agent unloads cleanly.

**Logging** records outcome, directory, and variable *names* (unset names at debug
level) — never values. A refusal's error message is shown to the user and also lands in
the daemon log, so it carries direnv's stderr tail, not the environment.

The hook keeps no state; every open re-evaluates (fact 2). That is also what makes
fail-closed hold over time: an `.envrc` edited after approval is blocked again by direnv,
and the next resume or reload is refused rather than quietly running the old environment.

## Client half: the header button

A `direnv` header button with `behavior: { kind: "menu" }`, registered in **every**
workspace (no per-workspace `.envrc` detection: that would need an RPC and keeping it
fresh). Registrations follow the workspace list subscription and are disposed when a
workspace goes away. Items:

- **Allow** — opens a workspace terminal running `direnv allow`. Runs immediately with no
  extra review step: the user pressing it is the deliberate act of trust.
- **Warm** — opens a workspace terminal running `direnv exec . true`, which evaluates the
  `.envrc` with no time limit and with output visible (nix build progress, evaluation
  errors), populating nix-direnv's cache so the next launch is fast. On a blocked
  `.envrc`, it shows direnv's own blocked error.

Both run in the workspace directory (fact 9). A failure to open the terminal surfaces as
paseo's standard error toast. After either, the user retries the create (the draft
prompt was kept) or uses Reload agent for an existing agent.

## Changed `.envrc`

No plugin mechanism. After editing an `.envrc` (and re-allowing it), the user picks
**Reload agent** from the agent's tab context menu (fact 10), which reopens the session
through the hook and gets the new environment — or a refusal if it is now blocked. This is
the documented path; automatic drift detection is a possible follow-up.

## Error handling summary

Fail closed on anything direnv itself considers unresolved: blocked, evaluation error,
timeout. Pass through only where direnv has no opinion: no binary, no `.envrc`, or a
history-only open. A refused open never leaves an agent running with a partial or
daemon-only environment.

## Testing seams

- The existing per-plugin flake checks: `paseo-plugin-direnv-typecheck` and
  `paseo-plugin-direnv-sdk-version`, which come with the `ts/` scaffolding.
- `paseo-plugin-requirements` covers the `requirements.paseo` range.
- Manual verification on a host, one workspace per case: allowed `.envrc` (agent sees the
  variables; `PATH` from the devshell), blocked `.envrc` (create refused with the Allow
  message; Allow then retry succeeds), failing `.envrc` (refused with stderr tail), slow
  `.envrc` (refused with Warm hint; Warm then retry succeeds), no `.envrc` (unchanged), a
  new worktree (blocked until allowed), resume after a daemon restart, and Reload agent
  after editing the `.envrc`.
