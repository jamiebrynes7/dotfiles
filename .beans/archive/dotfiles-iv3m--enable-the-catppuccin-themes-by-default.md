---
# dotfiles-iv3m
title: Enable the catppuccin themes by default
status: completed
type: task
priority: normal
created_at: 2026-10-05T13:35:30Z
updated_at: 2026-10-05T13:43:01Z
parent: dotfiles-6zzi
blocked_by:
    - dotfiles-m8y6
---

**Files:**
- Modify: `home/programs/paseo.nix` — default the catppuccin plugin on inside `lib.mkIf cfg.enable`, and mention it in the `plugins` description

Requested on 2026-10-05: the catppuccin themes should be available on every host that enables paseo, without per-host wiring. They are client-only theme data, so the default costs a host nothing beyond four extra entries under Settings → Appearance.

- [x] **Step 1: Default the plugin on**

In the `lib.mkIf cfg.enable` block, set `dotfiles.programs.paseo.plugins.catppuccin-theme.package = lib.mkDefault pkgs.dotfiles.paseo-plugin-catppuccin-theme;`. It is `mkDefault` so a host can point it elsewhere. A host opts out with `plugins.catppuccin-theme.enable = false`, which keeps the plugin configured but stopped.

- [x] **Step 2: Document the default**

Add a sentence to the `plugins` option description saying `catppuccin-theme` is configured by default, and how to turn it off.

- [x] **Step 3: Format**

Run: `nixfmt home/programs/paseo.nix`

- [x] **Step 4: Verify**

Render config.json for `{ enable = true; }` and confirm a `catppuccin-theme` entry pointing at the package's store path, plus `pluginsEnabled = true`. Then render with `plugins.catppuccin-theme.enable = false` and confirm the entry is present with `enabled: false`.

- [x] **Step 5: Commit**

```bash
git add home/programs/paseo.nix
git commit -m "home/programs/paseo: enable the catppuccin themes by default" -m "Bean: dotfiles-iv3m"
```

## Summary of Changes

Inside `lib.mkIf cfg.enable`, the module now sets `dotfiles.programs.paseo.plugins.catppuccin-theme.package` to `lib.mkDefault pkgs.dotfiles.paseo-plugin-catppuccin-theme`, and the `plugins` description documents the default and the opt-out.

Verified:
- **Default:** `{ enable = true; }` renders a `catppuccin-theme` directory entry plus `pluginsEnabled = true`.
- **Opt-out:** `plugins.catppuccin-theme.enable = false` renders the same entry with `enabled: false`.

Every host that enables paseo now gets the plugin. On the next switch after a lock bump, that changes the config and restarts the daemon.


**Review follow-up:**
- `pluginsEnabled` is now on only when at least one configured plugin is enabled. Without that, opting out of the default left the global switch on with nothing enabled. `settings.pluginsEnabled` still overrides it.
- The `plugins` example now shows the opt-out plus a fetched plugin, instead of repeating the default.
