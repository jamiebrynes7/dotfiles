---
# dotfiles-dist
title: Enable Codex's legacy Landlock sandbox backend on Linux
status: todo
type: task
priority: normal
created_at: 2026-09-01T14:22:54Z
updated_at: 2026-09-01T14:22:54Z
---

On an Ubuntu host with `kernel.apparmor_restrict_unprivileged_userns = 1`, every sandboxed Codex filesystem operation — the patch helper and `apply_patch` alike — fails before it can touch the repository:

```text
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

Codex and `bwrap` run under the `unconfined` AppArmor label, so the global restriction denies the unprivileged user namespace outright (`unshare: write failed /proc/self/uid_map: Operation not permitted`), and Bubblewrap then fails configuring the new netns loopback. Observed with Codex `0.144.4` and Bubblewrap `0.11.2` from `~/.nix-profile/bin/bwrap`: 21 consecutive Bubblewrap probes failed, and the same 21 probes passed with `codex sandbox -c features.use_legacy_landlock=true -- /bin/true`. Matches upstream [#15057](https://github.com/openai/codex/issues/15057) and [#14919](https://github.com/openai/codex/issues/14919); the [Codex Linux sandbox docs](https://github.com/openai/codex/blob/main/codex-rs/linux-sandbox/README.md) document `features.use_legacy_landlock` as the supported fallback.

dotfiles-040q put `pkgs.bubblewrap` on PATH on Linux, which does not help here — the Nix store path is not covered by a targeted Ubuntu AppArmor profile, and home-manager cannot install or reload root-owned profiles under `/etc/apparmor.d`.

## Todo

- [ ] Extend `managedConfig` in `home/programs/codex/default.nix` with `lib.optionalAttrs pkgs.stdenv.isLinux { "features.use_legacy_landlock" = "true"; }` — the module already renders it into the wrapper's `-c` flags, so no `~/.codex/config.toml` management is needed
- [ ] Decide whether `pkgs.bubblewrap` should stay on PATH once Landlock is the Linux default
- [ ] Verify on the affected host (rebuild home-manager, restart Codex, confirm a sandboxed edit succeeds)

Out of scope, recorded for context: the host-level alternative is a narrowly targeted AppArmor profile granting `userns` to a stable Codex wrapper path (not a hashed store path, which changes on upgrade). That needs root and belongs in host provisioning. Do not set `kernel.apparmor_restrict_unprivileged_userns = 0` — it weakens the policy for every unconfined process on the host. Until the fix lands, the workaround is approved escalation plus `git apply`, verifying the resulting diff touches only intended files.
