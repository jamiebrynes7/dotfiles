---
# dotfiles-jfs1
title: Validate the plugin path on a real host
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:29:46Z
updated_at: 2026-10-05T12:45:07Z
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

- [ ] **Step 0: Run the repo's own gate first**

Run: `nix flake check`

Expected: green.

- [ ] **Step 1: Inspect the live config before switching**

```bash
cat ~/.paseo/config.json
```

Anything beyond the creation defaults (`daemon.auth.password`, `providers`, `agentProfiles`, `terminalProfiles`, `features.dictation`) stops being read once Nix owns the file. Port it into `dotfiles.programs.paseo.settings` first, except a password, which moves to `PASEO_PASSWORD` via `environmentCommand`.

- [ ] **Step 2: Wire the plugin in and switch**

In dotfiles-samsara's `devbox/home.nix`, set `dotfiles.programs.paseo.plugins.devtools-auth.package`, bump the `dotfiles` input, then run `just switch-devbox`.

Expected: on the first switch only, activation prints the move-aside warning; it also prints the restart note.

- [ ] **Step 3: Verify the config is managed**

```bash
readlink ~/.paseo/config.json && cat ~/.paseo/config.json && ls ~/.paseo/config.json.daemon-* 2>/dev/null
```

Expected:
- `readlink` gives a `/nix/store/...` target.
- The config has `pluginsEnabled: true`, the `devtools-auth` entry pointing at the plugin's store path, and both `daemon.cors.allowedOrigins` and `app.baseUrl`.
- The old config is kept as `config.json.daemon-<timestamp>`.

- [ ] **Step 4: Verify the plugin loaded**

Run: `paseo plugin ls`

Expected: `devtools-auth` with status `running`. If it says `failed`, `paseo plugin logs devtools-auth` has the reason.

- [ ] **Step 5: Verify the plugin's UI**

In the app, a devbox workspace's header shows the devtools auth button, and its popover reports the token state.

- [ ] **Step 6: Verify the write guard**

Run: `paseo daemon set-password hunter2`

Expected: a failure that names `dotfiles.programs.paseo.settings`. Afterwards, `readlink ~/.paseo/config.json` should still point into the store.

- [ ] **Step 7: Verify restart-on-change, and only on change**

1. Change the plugin source or any `settings` value, then switch. Confirm the restart note printed and `paseo plugin ls` shows the new path.
2. Switch again with no changes. Confirm the daemon did *not* restart: a running agent session should survive.

- [ ] **Step 8: Record the result**

No commit. Before closing this bean, note anything surprising on it, especially any config key that had to be ported by hand. That list belongs in the spec's migration notes for the next host.
