# repo-skills: pairing a warning with its agent — spec

Date: 2026-11-06
Supersedes: docs/specs/2026-11-04-paseo-repo-skills.md §The Paseo plugin → Server half ("Warnings")

## Problem

`agent.create.before` has no agent id, so the original spec recorded each warning
against the agent's `cwd`. `agent.create.after` then took the oldest pending warning
for that `cwd`, and a short timeout dropped any whose creation never finished.

In Paseo 0.15.2, `createAgentInternal` can fail after `create.before` returns: the
provider-enabled check, client availability, and session config preparation all run
later. A retry in the same directory within the timeout would then be handed the
failed creation's warning.

## Decision

The warning travels with the request instead of being keyed by `cwd`:

1. `agent.create.before` records the warning under a random token and returns the
   request with `PASEO_REPO_SKILLS_WARNING=<token>` added to its `env`.
2. `agent.open.before` is called by `buildLaunchContext` with the agent id,
   `reason: "create"` and that env. It binds the token to the agent id and returns
   the env without the variable, so the agent process never sees it. It strips the
   variable on every open, because Paseo saves the creation env as the agent's
   `launchEnv` and passes it again on resume.
3. `agent.create.after` takes the warning for its agent id and appends the row.

A creation that fails before step 2 never binds its token. One that fails after it
leaves an entry under its id, which the next `create` open for that id clears. Both
expire after five minutes.

## Costs, accepted

- Paseo reloads every live agent's session on its next prompt whenever a plugin with
  an `agent.open.before` hook starts, stops or restarts. This plugin now has one.
- The token is not private. Plugin hooks that run after this one see it, and it stays
  in the agent's stored `launchEnv`.

## Related behaviour

- A stored agent that never got a provider session is re-created from its saved
  config, which already carries this plugin's `plugin-dir`. The hook treats its own
  value as unchanged rather than as "plugin-dir already set".
- Rows added with `timeline.append` do not survive a daemon restart: the timeline is
  rebuilt from the provider's history. The warning is visible when the agent is
  created and stays in the daemon log.
