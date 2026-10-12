---
# dotfiles-jfs1
title: Validate the plugin path on a real host
status: completed
type: task
priority: normal
created_at: 2026-09-21T17:29:46Z
updated_at: 2026-10-05T13:29:45Z
parent: dotfiles-5nj7
blocked_by:
    - dotfiles-j26a
    - dotfiles-uace
    - dotfiles-cxg5
---

**Files:** none. This is the manual validation pass from `docs/specs/2026-09-21-paseo-plugins.md`.

Nothing in this repo evaluates the home-manager module in CI (`nix flake check` builds packages only), and there is no test harness for module behaviour. This task is the end-to-end check on a host that actually runs the daemon.

**Retargeted (2026-10-05):** the first plugin through this path is `devtools-auth`. It lives downstream in `dotfiles-samsara` (`paseo-plugins/devtools-auth/`, packaged as `packages/paseo-plugin-devtools-auth`) and is validated on a devbox. catppuccin (dotfiles-m8y6) is deferred and no longer blocks this task.

**Run the switch from a shell outside paseo.** The first switch restarts the daemon, which kills any agent session running inside it, including the one doing this work.

- [x] **Step 0: Run the repo's own gate first**

Run: `nix flake check`

Expected: green.

- [x] **Step 1: Inspect the live config before switching**

```bash
cat ~/.paseo/config.json
```

Anything beyond the creation defaults (`daemon.auth.password`, `providers`, `agentProfiles`, `terminalProfiles`, `features.dictation`) stops being read once Nix owns the file. Port it into `dotfiles.programs.paseo.settings` first, except a password, which moves to `PASEO_PASSWORD` via `environmentCommand`.

- [x] **Step 2: Wire the plugin in and switch**

In dotfiles-samsara's `devbox/home.nix`, set `dotfiles.programs.paseo.plugins.devtools-auth.package`, bump the `dotfiles` input, then run `just switch-devbox`.

Expected: on the first switch only, activation prints the move-aside warning; it also prints the restart note.

- [x] **Step 3: Verify the config is managed**

```bash
readlink ~/.paseo/config.json && cat ~/.paseo/config.json && ls ~/.paseo/config.json.daemon-* 2>/dev/null
```

Expected:
- `readlink` gives a `/nix/store/...` target.
- The config has `pluginsEnabled: true`, the `devtools-auth` entry pointing at the plugin's store path, and both `daemon.cors.allowedOrigins` and `app.baseUrl`.
- The old config is kept as `config.json.daemon-<timestamp>`.

- [x] **Step 4: Verify the plugin loaded**

Run: `paseo plugin ls`

Expected: `devtools-auth` with status `running`. If it says `failed`, `paseo plugin logs devtools-auth` has the reason.

- [x] **Step 5: Verify the plugin's UI**

In the app, a devbox workspace's header shows the devtools auth button, and its popover reports the token state.

- [x] **Step 6: Verify the write guard**

Run: `paseo daemon set-password hunter2`

Expected: a failure that names `dotfiles.programs.paseo.settings`. Afterwards, `readlink ~/.paseo/config.json` should still point into the store.

- [x] **Step 7: Verify restart-on-change, and only on change**

1. Change the plugin source or any `settings` value, then switch. Confirm the restart note printed and `paseo plugin ls` shows the new path.
2. Switch again with no changes. Confirm the daemon did *not* restart: a running agent session should survive.

- [x] **Step 8: Record the result**

No commit. Before closing this bean, note anything surprising on it, especially any config key that had to be ported by hand. That list belongs in the spec's migration notes for the next host.

## Summary of Changes

Validated on a devbox (the dotfiles-samsara devbox config) with the devtools-auth plugin, on paseo 0.10.3:
- **Config:** `~/.paseo/config.json` is a store link with `pluginsEnabled`, the `devtools-auth` entry and both creation defaults. The first switch moved the daemon-written file to `config.json.daemon-20261005132153`.
- **Plugin:** `paseo plugin ls` shows `devtools-auth` running, and its header button and popover work in the app.
- **Restart on change:** a second switch with a changed plugin store path restarted the daemon and loaded the new path.
- **No-change switch:** a `--dry-run` switch with nothing changed ran onFilesChange without the restart note. It also completed over the managed file, which checks the `force` fix for dry runs.
- **Write guard:** `paseo daemon config set` was refused with the guard message, and the symlink was untouched.

Surprises for the migration notes:
- **Step 6 no longer exercises the guard.** `paseo daemon set-password` now needs a TTY and exits before writing, so the guard was checked through `paseo daemon config set` (same savePersistedConfig path).
- **Nothing to port.** The daemon-written config held only the creation defaults plus `daemon.listen` and `daemon.relay`. Both are already set by the module's env and `--no-relay`, so nothing went into `settings`.
