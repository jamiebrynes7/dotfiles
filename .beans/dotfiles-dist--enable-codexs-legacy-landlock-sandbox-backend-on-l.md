---
# dotfiles-dist
title: Fix the Codex bwrap sandbox on AppArmor-restricted Linux hosts
status: completed
type: task
priority: normal
created_at: 2026-09-01T14:22:54Z
updated_at: 2026-09-04T10:10:26Z
---

On an Ubuntu host with `kernel.apparmor_restrict_unprivileged_userns = 1`, every sandboxed Codex filesystem operation — the patch helper and `apply_patch` alike — fails before it can touch the repository:

```text
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

Codex and `bwrap` run under the `unconfined` AppArmor label, so the global restriction denies the unprivileged user namespace outright (`unshare: write failed /proc/self/uid_map: Operation not permitted`), and Bubblewrap then fails configuring the new netns loopback. Observed with Codex `0.144.4` and Bubblewrap `0.11.2` from `~/.nix-profile/bin/bwrap`: 21 consecutive Bubblewrap probes failed, and the same 21 probes passed with `codex sandbox -c features.use_legacy_landlock=true`. Matches upstream [#15057](https://github.com/openai/codex/issues/15057) and [#14919](https://github.com/openai/codex/issues/14919); the [Codex Linux sandbox docs](https://github.com/openai/codex/blob/main/codex-rs/linux-sandbox/README.md) document `features.use_legacy_landlock` as the supported fallback.

dotfiles-040q put `pkgs.bubblewrap` on PATH on Linux, which does not help here — the Nix store path is not covered by a targeted Ubuntu AppArmor profile (those attach by absolute binary path), so it runs unconfined and is denied.

## Approach

Ship both fixes and let the host pick, rather than only the workaround:

- `codex-apparmor-setup` installs an AppArmor profile granting `userns` to `/nix/store/*/bin/bwrap`, making the default bwrap backend work properly. This is the actual fix.
- `useLegacyLandlock` (new option, **default `false`**) switches Codex to the Landlock backend for hosts that would rather not carry root-owned host state. Defaulting off keeps every other host on upstream's default backend; the flag is named "legacy" and may not outlive the bug, so no host should inherit it silently.
- A shared bwrap probe gates codex startup, so a host where neither has been done fails fast with an actionable message instead of failing cryptically mid-session.

Do **not** set `kernel.apparmor_restrict_unprivileged_userns = 0` — it weakens the policy for every unconfined process on the host.

### Design decisions

- **Probe bwrap, don't infer from the filesystem.** Checking the sysctl plus `/etc/apparmor.d/nix-bwrap` is a Debian-ism that says nothing on NixOS, where profiles come from `security.apparmor.policies` and never land at that path. Running bwrap tests the actual capability, so it is correct on every distro — the same methodology as the 21-probe diagnosis above.
- **One probe binary, three call sites** (wrapper, activation, installer). The installer must not re-implement the check it exists to satisfy, or it could report success while the wrapper still refuses to start. Only the per-site *messages* differ.
- **The wrapper bails; activation only warns.** A failed probe means every sandboxed operation in the session will fail. Making activation fatal would instead brick `home-manager switch` on that host.
- **The installer stays imperative and out of activation.** It writes root-owned state under `/etc`; activation runs unprivileged and has no tty on the NixOS systemd path, so escalating from it either hangs or needs a sudoers rule that is itself root-provisioned state.
- **Profile attaches by glob.** `*` matches a single path component, so `/nix/store/*/bin/bwrap` covers every store path without regeneration on upgrade. Granting `userns` to bubblewrap alone is far narrower than flipping the sysctl.

## Todo

- [x] Add `home/programs/codex/nix-bwrap.apparmor` — profile attaching to `/nix/store/*/bin/bwrap` with `userns`, mirroring Ubuntu's own bwrap profile. Omit the `abi` pragma initially (a missing abi is a hard parse error and the available one varies by release); confirm with `apparmor_parser -Q` on the host.
- [x] Add the shared `bwrapUsernsProbe` `let` binding (`pkgs.writeShellScript`) running `bwrap --unshare-user --unshare-net --ro-bind / / /bin/true`. Do not silence bwrap — callers redirect when they want quiet.
- [x] Add `home/programs/codex/apparmor-setup.sh` + `pkgs.writeShellApplication` wiring: refuse on non-Linux; refuse on NixOS pointing at `security.apparmor.policies`; require `apparmor_parser`; probe first and exit 0 if already working (no sudo); validate with `apparmor_parser -Q`; `sudo install` + `sudo apparmor_parser -r`; re-probe letting stderr through. Add `--dry-run`.
- [x] Add the `useLegacyLandlock` option (`types.bool`, `default = false`) beside `enableHooks`.
- [x] Extend `managedConfig` with `lib.optionalAttrs (pkgs.stdenv.isLinux && cfg.useLegacyLandlock) { "features.use_legacy_landlock" = "true"; }` — the module already renders it into the wrapper's `-c` flags, so no `~/.codex/config.toml` management is needed.
- [x] Add `mkBwrapUsernsCheck onFailure`, guarded on `pkgs.stdenv.isLinux && !cfg.useLegacyLandlock`, with a `DOTFILES_CODEX_SKIP_SANDBOX_CHECK` escape hatch. Wire the wrapper with `"exit 1"` and activation (appended to the existing `codexStableLink` entry) with `""`.
- [x] Add `apparmorSetup` to `home.packages` beside `pkgs.bubblewrap` and update that comment. **Resolved:** bubblewrap stays on PATH — with `useLegacyLandlock` defaulting to false it is the active backend, and the installer's whole purpose is making it work.
- [x] Verify the probe has no false positives on a healthy Linux host — **moved to dotfiles-t4q7**, needs a Linux host. (Review caught one such false positive already: the probe originally execd `/bin/true`, absent on NixOS.)
- [x] Verify by eval on darwin: Linux default emits the probe and no `use_legacy_landlock`; `useLegacyLandlock = true` flips both; darwin emits neither and — critically — still *evaluates*, proving no consumer escaped its `lib.optionals` guard and forced `pkgs.bubblewrap` on darwin.
- [x] Verify the rendered `codex-apparmor-setup` and the rendered wrapper reference the *same* probe store path (the sharing is the point; a copy-paste would look identical until it drifted).
- [x] `nixfmt --check` and `nix flake check`. (darwin; CI covers x86_64-linux)
- [x] Verify end to end on the affected Ubuntu host — **moved to dotfiles-t4q7**, cannot be done from darwin. Includes settling the omitted `abi` pragma.

## Summary of Changes

Shipped both fixes for the AppArmor/bwrap breakage rather than only the Landlock workaround.

**`home/programs/codex/nix-bwrap.apparmor`** (new) — profile attaching to `/nix/store/*/bin/bwrap` with `userns`, mirroring Ubuntu's own bwrap profile. The glob attachment survives store-path changes on upgrade. No `abi` pragma; see dotfiles-t4q7 for settling that on the host.

**`home/programs/codex/apparmor-setup.sh`** (new) — `codex-apparmor-setup`, installed on Linux. Refuses on darwin and on NixOS (printing the real profile so the guidance cannot drift), requires apparmor_parser and an active AppArmor, validates with `apparmor_parser -Q` before escalating, probes first so re-runs need no sudo, installs and reloads with diagnosed failures on both sudo calls, then re-probes letting bwrap's own error through. `--dry-run` previews unconditionally.

**`home/programs/codex/default.nix`** — `bwrapUsernsProbe` as the single definition of the capability check, shared by all three call sites (verified: the installer and the wrapper reference the identical store path). `mkBwrapUsernsCheck` renders it with `bwrapCheckFatal` / `bwrapCheckWarn`; the wrapper bails, the new `codexSandboxCheck` activation entry only warns so it cannot brick `home-manager switch`. `useLegacyLandlock` (default `false`) injects `-c features.use_legacy_landlock=true` via `managedConfig`, guarded on platform as well as option. `codex-apparmor-setup` joins bubblewrap on PATH.

### Review

A subagent review returned two blocking findings, both fixed: the probe exec'd `/bin/true`, which does not exist on NixOS (whose `/bin` holds only `sh`) and would have permanently bricked codex there; and the two new files were untracked, which breaks flake evaluation on every platform. Eleven further findings applied. The reviewer confirmed the darwin laziness guards are airtight — `pkgs.bubblewrap` genuinely throws on darwin eval, so those guards are load-bearing.

One finding was raised and declined by the user: the wrapper's `exit 1` also gates invocations that never touch the sandbox (`codex --version`, `login`, `mcp`, `--dangerously-bypass-approvals-and-sandbox`). Kept bailing on everything for predictability; `DOTFILES_CODEX_SKIP_SANDBOX_CHECK` is the escape hatch.

### Verified

Eval on x86_64-linux and aarch64-darwin (both option states), shellcheck on the rendered installer, `nixfmt --check`, `nix flake check`. Note that `checks` instantiates no home-manager configuration, so **nothing in CI evaluates this module** — dotfiles-d6t2 would close that gap.

### Follow-ups

- dotfiles-t4q7 — on-host verification (high; the `abi` pragma is the main open risk)
- dotfiles-5244 — declarative opt-out for the activation warning
- dotfiles-s6ym — uninstall path for the profile
