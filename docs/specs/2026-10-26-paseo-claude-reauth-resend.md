# claude-reauth: spent cards and automatic resend — spec

Date: 2026-10-26
Supersedes: docs/specs/2026-10-22-paseo-claude-reauth-plugin.md §Non-goals ("No re-sending the failed message"), §Client half ("`done` … also re-enables them"), §Contracts (`RecoveryState`)

Two changes to the `claude-reauth` plugin, both from using it:

1. Once a recovery has reloaded the agent, the card that started it (and any older card
   for that agent) is **spent**: its buttons are grayed out and can't be pressed.
2. After a successful reload the daemon **resends the failed message** itself, when it can
   tell which message failed and that resending is safe. Otherwise the card still says
   "send your message again".

Everything else in the 2026-10-22 spec stands.

## Upstream facts this design depends on

Checked against `@getpaseo/plugin`, `@getpaseo/client` and `@getpaseo/protocol` 0.13.0
(the pinned version). 0.13.0 still exposes no agent reload to plugins, so the reload stays
on `paseo agent reload`.

- **The server half can send messages.** Every RPC handler gets a `PluginHandlerContext`
  with `paseo: PaseoApi`. `paseo.agents.ref(agentId).send(text)` sends a user message, and
  `.timeline.refetch({ direction: "tail", limit })` returns the newest timeline entries.
- **Timeline entries** (`AgentTimelineEntryPayloadSchema`) carry `item` and a `timestamp`
  (ISO string). A `user_message` item has `text` and optional `messageId`/`clientMessageId`,
  but **no images**. After a reload that text is read back from Claude's session history,
  which joins every text block of the prompt, so text attachments (chat history,
  rendered PR/review attachments) come back inlined into it. A resend can only be that
  text: images are lost and text attachments are resent as part of the message.
- **The card knows its own time.** `PluginTimelineItemProps` gives the renderer a
  `timestamp: Date` for the item it renders.
- **Reload re-streams history**, including the auth-error reply (see commit 58cee61), so
  after `paseo agent reload` the agent's timeline still ends with that reply unless
  something was sent since. The agent is live after the reload, so refetching its
  timeline is safe: the repo's warning about `timeline.refetch` applies only to agents the
  client hasn't seen live.

## Contracts

```ts
type RecoveryState =
  | { phase: "idle" }
  | { phase: "logging-in"; url?: string }
  | { phase: "reloading" }
  | { phase: "resending" }
  | { phase: "done"; at: string; resent: boolean }   // at: ISO time the run ended
  | { phase: "failed"; step: "login" | "reload" | "resend"; error: string; url?: string; at: string };

// What start and status now return.
type Recovery = { state: RecoveryState; lastDoneAt?: string };
```

`start` and `status` keep their inputs but now return `Recovery`. `lastDoneAt` is when
the agent's latest successful recovery ended. Unlike `done`, a later run doesn't
overwrite it. `resending` counts as running, like `logging-in` and `reloading`: `start`
returns the current state without starting anything, and the card polls.

## Server half: resend after reload

After `paseo agent reload` exits 0, the job moves to `resending` and then:

1. Refetches the agent's timeline tail: a small page, enough for the last two entries.
2. Checks the **resend rule**: the last entry is an `assistant_message` that
   `matchAuthFailure(text, "complete")` accepts (the same shared detector the card uses),
   **and** the entry right before it is a `user_message`. Anything else means no resend,
   including:
   - an empty or short page;
   - the user has already sent something else;
   - tool calls or reasoning came between the message and the error, so the turn did work
     that a resend might repeat.
3. If the rule holds, sends that `user_message`'s `text` unchanged with
   `agents.ref(agentId).send(text)`. Nothing marks it as a resend.
4. Becomes `done { at, resent }`, where `resent` says whether step 3 ran. `at` is taken
   **before** step 1, not after the send. A resent message that fails auth again can
   be answered before `send` resolves, and its new card must be newer than `at` to
   work. Re-streamed history keeps its original timestamps, so it stays older. The
   same `at` becomes `lastDoneAt`.

Failures:

- The refetch or the send throws → `failed { step: "resend", error }`. The reload
  itself worked, so the card's message tells the user to send the message by hand. The
  buttons come back on, as for any `failed`.
- A failed resend is never retried automatically.
- If the plugin stops while the refetch is in flight, nothing is sent.

Both buttons resend: **Reload only** follows the same reload → resend path.

## Client half: spent cards

- A card is **spent** when `lastDoneAt` is later than the card's own `timestamp`. A
  spent card grays out both buttons (the existing `disabled` style) and keeps showing
  the status line. It stays spent while a later run goes and after that run fails.
- A card newer than the last successful recovery is not spent. So an auth error that
  shows up after a recovery (for example, the resent message fails because the login
  didn't take) gets a working card, and pressing it starts a new run.
- A `done` or `failed` whose `at` is earlier than the card's `timestamp` belonged to an
  earlier auth error. The card reads it as `idle`, so it never shows an unrelated
  run's result.
- On a card that isn't spent, `failed` still turns both buttons back on.
- Status lines:
  - `resending` → "Resending your message…"
  - `done`, `resent: true` → "Reloaded and resent your message"
  - `done`, `resent: false` → "Reloaded — send your message again"
  - `failed`, `step: "resend"` → "Reloaded, but resending failed: <error> — send your
    message again"
- **After a daemon restart** state is lost, every card reads `idle` again, and old cards
  can be pressed again. This is accepted, as before: a restart reloads agents anyway, and
  pressing an old card is harmless.

## Error handling summary

Additions to the 2026-10-22 table:

| Situation | What the user sees |
|---|---|
| Timeline doesn't end in user message → auth error | Reloaded — send your message again |
| Original message had images | Text is resent without them (can't be detected) |
| Original message had text attachments | Resent with their text inlined into the message |
| Timeline refetch or send fails | Reloaded, but resending failed: error |
| Resent message fails auth again | New card with working buttons, below the spent one |

## Testing seams

- The existing `paseo-plugin-claude-reauth-typecheck` and `-sdk-version` flake checks.
- Manual verification on a host (`claude auth logout`, then message a live agent):
  - **Log in & reload** resends the message, and the card turns gray with "Reloaded and
    resent your message";
  - **Reload only** after logging in from a shell does the same;
  - sending something by hand before pressing the button gives `resent: false`, and the
    resend is skipped;
  - with the login left broken, the resent message fails again and produces a new card
    with working buttons, while the old card stays gray;
  - a second device shows the spent card as gray.
