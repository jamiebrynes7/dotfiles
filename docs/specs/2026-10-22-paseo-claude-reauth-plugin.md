# A Claude re-auth paseo plugin — spec

Date: 2026-10-22

A repo-local paseo plugin, `claude-reauth`, that recognises a Claude agent's expired-login
reply in the chat and replaces it with a card offering **Log in & reload** and **Reload
only**. The daemon half runs `claude auth login` and then `paseo agent reload <id>`, so
recovering no longer needs a shell.

Context: [getpaseo/paseo#3325](https://github.com/getpaseo/paseo/issues/3325) asks core
for exactly this ("Re-authenticate" affordance, re-check credentials, map `/login`). It is
open at p2 with no maintainer decision on its shape. The documented workaround is to log in
outside Paseo, then `paseo agent reload <id>`, which keeps the conversation. This plugin
automates that workaround and does nothing more.

## Goals

- When a Claude agent replies with an expired or revoked login, the reply shows as a card
  in the chat rather than as plain text, on live turns and on reopened history alike.
- One click from any client device logs in on the daemon host and reloads that agent,
  keeping its conversation.
- One click reloads an agent without logging in again, for when the login was already done
  (from another agent's card, or a shell).
- Every failure names the step that broke (login or reload) and shows its error. A login
  that stalls shows the login URL as a link.

## Non-goals

- **No re-sending the failed message.** After a reload the user sends again. The plugin
  can't tell whether resending is safe or still wanted.
- **No proactive detection.** Nothing polls `claude auth status` or watches credential
  files. The trigger is only the failure message in the timeline.
- **No other providers.** Codex has the same dead end (#5740 on #3325), but its message and
  login command differ. The detector and login runner are Claude-specific by design.
- **No bulk reload.** Each card reloads its own agent. Other affected agents use their own
  card's **Reload only**.
- **No persisted state.** Recovery state lives in the daemon half's memory. After a daemon
  restart every card reads idle again, which is harmless since a restart reloads agents
  anyway.

## Upstream facts this design depends on

All verified against paseo 0.12.0 (the pinned version) and Claude Code 2.1.258.

- **What Claude emits.** On an expired login Claude Code writes a synthetic assistant
  message with `error: "authentication_failed"`, `isApiErrorMessage: true`,
  `model: "<synthetic>"`, zero tokens, and text
  `Failed to authenticate: OAuth session expired and could not be refreshed` (seen in a
  local `~/.claude/projects` session launched with `entrypoint: "sdk-cli"`, i.e. by paseo).
- **What paseo keeps.** paseo's Claude provider never reads the `error` field (no reference
  to `authentication_failed` anywhere in `packages/server`). The text reaches the timeline
  as a plain `assistant_message`, and the turn may well read as completed (compare #7636).
  So detection must match **text**. Text produced by a real `turn_failed` takes a
  different path: `appendSystemErrorTimelineMessage` prefixes it with
  `SYSTEM_ERROR_PREFIX`, still as text. The matcher looks for a known phrase anywhere in
  the text, not at the start, so both paths are caught.
- **Timeline transformers apply to history.** The app's projection
  (`packages/app/src/plugins/timeline/projection.ts`) runs every registered transformer
  over every source item, live or loaded. An assistant message reads `phase: "complete"`
  once it has finished streaming. The transformer must return items of `type: "plugin"`
  with a kind matching `^[a-z][a-z0-9-]*$`, an integer `version ≥ 1`, and JSON-compatible
  `data`. Returning `undefined` leaves the item untouched.
- **Plugin RPCs time out at 30 s** (`REQUEST_TIMEOUT_MS` in
  `packages/server/src/server/plugins/runtime.ts`). A browser login routinely takes longer,
  so no RPC may wait on the login or the reload. Both run as background jobs that the
  client polls.
- **The plugin API has no reload.** `PaseoApi` exposes `agents.list/ref/create/subscribe`,
  and `PaseoAgentHandle.refresh()` only re-fetches the snapshot. The real reload is
  `DaemonClient.refreshAgent` (`refresh_agent_request`), which plugins can't reach.
  `paseo agent reload <id>` calls exactly that. It interrupts a running turn, reloads the
  provider session from disk and keeps the timeline.
- **The daemon half inherits the daemon's environment.** Plugin workers are `fork`ed with
  no `env` override, so they see the daemon's `PATH` (which the home-manager module builds
  to include `~/.local/bin`, where `claude` lives) and `PASEO_HOME`. `paseo` with
  `PASEO_HOME` set targets that daemon. The user confirmed `paseo` is on the daemon's
  `PATH`.
- **Login opens URLs on the host.** `claude auth login` opens its URL with the host's
  opener. On this fleet that is the host's browser on macOS, and the `xdg-open` forwarding
  wrapper on devboxes. So the daemon half can run it with no terminal, whichever device
  the click came from. It takes `--claudeai` (the default), `--console`, `--sso` and
  `--email`. The plugin passes no flags.
- **`claude auth status` can't confirm recovery.** It reports `loggedIn: true` from the
  credential's presence, including while that credential is the expired one. The plugin
  does not use it. Success means the login process exited 0 and the reload succeeded.

## Architecture

One plugin with both halves, laid out as the daemon's loader requires: root modules are
only `index.client.ts(x)` and `index.server.ts`, and everything else goes under `client/`,
`server/` or `shared/`. It is packaged like `last-response` (`buildPaseoPlugin`, one-line
`packages/paseo-plugin-claude-reauth/default.nix`) and enabled by default next to the
other repo-local plugins in `home/programs/paseo.nix`.

```
assistant_message ──transformer──► plugin item { kind: "auth-expired" }
                                          │ renderer
                                          ▼
                                     AuthCard ──rpc start / poll status──► daemon half
                                                                            ├─ login job (one, shared)
                                                                            │    claude auth login
                                                                            └─ recovery job (per agent)
                                                                                 paseo agent reload <id>
```

Units:

- **Detector** (shared): a pure `matchAuthFailure(text): boolean` over a list of known
  phrases, matched as case-sensitive substrings: `OAuth session expired`,
  `OAuth access token has been revoked`, and `Not logged in · Please run /login`. Supporting
  a new wording means adding one entry. A miss degrades to today's behaviour, a plain
  message.
- **RPC contracts** (shared): `start` and `status`, below.
- **Transformer + renderer** (client): matches, then swaps in the card.
- **AuthCard** (client): renders state, starts jobs, polls.
- **Job runner** (server): owns the login child process and per-agent recovery state.

## Contracts

```ts
type RecoveryState =
  | { phase: "idle" }
  | { phase: "logging-in"; url?: string }
  | { phase: "reloading" }
  | { phase: "done" }
  | { phase: "failed"; step: "login" | "reload"; error: string; url?: string };

// start: kicks off a recovery for one agent and returns at once.
start(input: { agentId: string; login: boolean }): RecoveryState;
// status: current state for one agent; "idle" if it has never been started.
status(input: { agentId: string }): RecoveryState;
```

The timeline item is `{ type: "plugin", kind: "auth-expired", version: 1,
data: { message: string } }`. `data.message` is the original text, shown on the card so no
information is lost.

## Server half: jobs

- **Recovery state** is a `Map<agentId, RecoveryState>`. `start` on an agent already
  `logging-in` or `reloading` is a no-op that returns the current state, so a double click
  or a second client can't stack jobs. `start` from `idle`, `done` or `failed` begins a new
  run.
- **Login job**: at most one `claude auth login` at a time, shared by every agent that
  asked for it. Agents that call `start({ login: true })` while it runs wait on the same
  promise. The child runs with stdin ignored and no flags. The first `https://` URL in its
  stdout or stderr is recorded onto every waiting agent's state as `url`.
  - Exit 0 → each waiting agent moves to `reloading`.
  - Non-zero exit → `failed` with `step: "login"`, the stderr tail as `error`, and `url` if
    one was seen.
  - No exit within **5 minutes** → the child is killed and the agent fails with the same
    shape and the error `login timed out`.
- **Reload job**: `paseo agent reload <agentId>` with a **2 minute** timeout. Exit 0 →
  `done`. Otherwise → `failed` with `step: "reload"` and the stderr tail.
- **Cleanup**: the contribution's cleanup kills any running child, so a plugin reload or a
  daemon stop leaves nothing behind.
- No agent lookup is done before reloading. If the id is unknown, `paseo agent reload`
  fails, and that error is what the card shows.

## Client half: the card

- The transformer is registered for `itemType: "assistant_message"`. It returns the plugin
  item only when `phase === "complete"` and `matchAuthFailure(item.text)`, and `undefined`
  otherwise, so a reply that is still streaming isn't swapped out halfway.
- The card shows:
  - a title, "Claude login expired";
  - the original message;
  - **Log in & reload** (`start({ login: true })`) and **Reload only**
    (`start({ login: false })`);
  - a status line for the current phase.
- When it mounts, the card calls `status` once, so a card on another device, or reopened
  mid-run, shows a job already in flight. While the phase is `logging-in` or `reloading` it
  polls `status` every **2 s** and stops once the phase settles.
- `logging-in` reads "Finish signing in in the browser on your host". When a `url` is
  present it also shows "Open login page" as a link via `openExternalUrl`. That opens the
  link on the device being used, which is the right fallback when the host's browser didn't
  open.
- `failed` shows the step and the error, and re-enables both buttons. `done` reads "Reloaded
  — send your message again" and also re-enables them.
- Because the card is stateless, an old auth error in history keeps rendering as a card
  forever, reading `idle` after a daemon restart. Pressing its buttons is harmless: a login
  you didn't need, or a reload.
- If a poll fails, for example while the daemon half restarts, the card keeps its last
  state and retries on the next tick. If the daemon half is unreachable, `start` fails, and
  the card shows that error without changing phase.

## Error handling summary

| Failure | What the user sees |
|---|---|
| Message wording not in the detector | Plain message, as today |
| `claude auth login` exits non-zero | Card: login failed, stderr tail, URL link if seen |
| Login stalls (prompt, browser never opened) | After 5 min: login timed out, URL link if seen |
| `claude` or `paseo` not on the daemon's `PATH` | Failed at that step, with the spawn error (`ENOENT`) |
| `paseo agent reload` fails or times out | Card: reload failed, stderr tail |
| Reload succeeds but the login didn't take | Next message fails again and shows a fresh card |
| Daemon half unreachable | `start` error shown; polling retries |

## Testing seams

- The existing per-plugin flake checks that come with the `ts/` scaffolding:
  `paseo-plugin-claude-reauth-typecheck` and `paseo-plugin-claude-reauth-sdk-version`.
- `paseo-plugin-requirements` covers the `requirements.paseo` range.
- Manual verification on a host:
  - a card appears for a matching message, both live and after reopening the chat;
  - **Reload only** reloads and the conversation survives;
  - **Log in & reload** opens the host browser, and finishing the login moves the card to
    done;
  - closing the browser without finishing reaches the timeout and shows the URL link;
  - two cards started together share one login;
  - a card on a second device shows the in-flight phase.

  To reproduce the message on demand, `claude auth logout` on the host, then message a
  live agent.
