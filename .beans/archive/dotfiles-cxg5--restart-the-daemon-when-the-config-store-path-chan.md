---
# dotfiles-cxg5
title: Restart the daemon when the config store path changes
status: completed
type: task
priority: normal
created_at: 2026-09-21T17:29:14Z
updated_at: 2026-10-05T12:44:20Z
parent: dotfiles-eii4
blocked_by:
    - dotfiles-t4ve
---

**Files:**
- Modify: `home/programs/paseo.nix` — add `restartDaemon` to the `let` block, and set `home.file."<dataDirRelative>/config.json".onChange` inside the `lib.mkIf cfg.service.enable` block

Why this is needed: home-manager reloads a launchd agent only when the plist changes, and nothing in the unit depends on `config.json`. The daemon reads plugins once, in `start()` (`plugins/index.ts`); `paseo reload` re-reads the file but does not re-activate plugin source entries, and `reloadPlugin` uses the in-memory path. So a plugin bump (a new store path in the config) takes effect only on a restart.

**Revised approach (2026-10-05):** the original plan carried the old link target from the move-aside entry to a separate `paseoRestart` entry through a shell variable, and compared it there. home-manager already does this comparison: `home.file.<name>.onChange` runs during `onFilesChange`, after `linkGeneration`, and only when `checkFilesChanged` found that the file's content differs from the previous generation. The plugin store paths are part of the rendered content, so a plugin bump changes it. A first switch over a daemon-written file also counts as a change.

- [x] **Step 1: Add the platform-specific restart to the `let` block**

On Darwin, `launchctl kickstart -k gui/$(id -u)/org.nix-community.home.paseo`, guarded on `launchctl print` succeeding for that label. On Linux, `systemctl --user try-restart paseo.service`, which does nothing when the unit is inactive. Both use `run`, so `--dry-run` restarts nothing, and both print a `noteEcho`.

- [x] **Step 2: Hook it to the config file**

In the `lib.mkIf cfg.service.enable` element, set `home.file."${dataDirRelative}/config.json".onChange = restartDaemon;`. Without `service.enable` there is no unit to restart, so `onChange` stays empty.

- [x] **Step 3: Format**

Run: `nixfmt home/programs/paseo.nix`

- [x] **Step 4: Verify the generated hook**

Evaluate `hm.config.home.file.".paseo/config.json".onChange` for `{ enable = true; service.enable = true; }` on `x86_64-linux` and on `aarch64-darwin`. Expected: `systemctl --user try-restart` and `launchctl kickstart -k` respectively.

- [x] **Step 5: Verify it is empty without `service.enable`**

Expected: `onChange` is `""`.

- [x] **Step 6: Commit**

```bash
git add home/programs/paseo.nix
git commit -m "home/programs/paseo: restart the daemon when config.json changes" -m "Bean: dotfiles-cxg5"
```

## Summary of Changes

The daemon restart now hangs off home-manager's `home.file.<config.json>.onChange`, set only when `service.enable` is on. home-manager runs it after `linkGeneration`, and only when the rendered content differs from the previous generation. Darwin uses a guarded `launchctl kickstart -k` and Linux uses `systemctl --user try-restart`, both through `run`. Evaluating both systems gives the expected script with `service.enable` and an empty one without it.
