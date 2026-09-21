---
# dotfiles-jfs1
title: Validate the plugin path on a real host
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:29:46Z
updated_at: 2026-09-21T17:30:11Z
parent: dotfiles-5nj7
blocked_by:
    - dotfiles-j26a
    - dotfiles-m8y6
    - dotfiles-uace
    - dotfiles-cxg5
---

**Files:** none — this is the manual validation pass from `docs/specs/2026-09-21-paseo-plugins.md`.

Nothing in this repo evaluates the home-manager module in CI (`nix flake check` builds packages only), and there is no test harness for module behaviour. This task is the end-to-end check on a host that actually runs the daemon.

- [ ] **Step 0: Run the repo's own gate first**

Run: `nix flake check`

Expected: green. This builds the patched paseo and every plugin package on both systems, and is what CI runs — get it passing before touching a host.

- [ ] **Step 1: Inspect the live config before switching**

```bash
cat ~/.paseo/config.json
```

Anything beyond the creation defaults — `daemon.auth.password`, `providers`, `agentProfiles`, `terminalProfiles`, `features.dictation` — stops being read once Nix owns the file. Port it into `dotfiles.programs.paseo.settings` first, except a password, which moves to `PASEO_PASSWORD` via `environmentCommand`.

- [ ] **Step 2: Wire the plugin in and switch**

In the host's home configuration:

```nix
dotfiles.programs.paseo.plugins.catppuccin-theme.package =
  pkgs.dotfiles.paseo-plugin-catppuccin-theme;
```

Then run the host's usual switch command.

Expected: activation prints the move-aside warning (first switch only) and the restart note.

- [ ] **Step 3: Verify the config is managed**

```bash
readlink ~/.paseo/config.json && cat ~/.paseo/config.json && ls ~/.paseo/config.json.daemon-* 2>/dev/null
```

Expected: a `/nix/store/...` target; `pluginsEnabled: true`, the `catppuccin-theme` entry pointing at the plugin store path, and `daemon.cors.allowedOrigins` / `app.baseUrl` present; the pre-existing config preserved as `config.json.daemon-<timestamp>`.

- [ ] **Step 4: Verify the plugin loaded**

```bash
paseo plugin ls
```

Expected: `catppuccin-theme` with status `running`. If it says `failed`, `paseo plugin logs catppuccin-theme` has the reason.

- [ ] **Step 5: Verify the themes appear**

In the app: Settings → Appearance lists Catppuccin Latte, Frappé, Macchiato and Mocha.

- [ ] **Step 6: Verify the write guard**

```bash
paseo daemon set-password hunter2
```

Expected: failure naming `dotfiles.programs.paseo.settings`. Confirm `readlink ~/.paseo/config.json` still points into the store afterwards.

- [ ] **Step 7: Verify restart-on-change, and only on change**

Bump the plugin pin (or change any `settings` value), switch, and confirm the restart note printed and `paseo plugin ls` shows the new path. Then switch again with no changes and confirm the daemon was *not* restarted — check that a running agent session survives.

- [ ] **Step 8: Record the result**

No commit. Note anything surprising on this bean before closing it, especially any config key that had to be ported by hand — that list belongs in the spec's migration notes for the next host.
