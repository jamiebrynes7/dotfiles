---
# dotfiles-t4q7
title: Verify the nix-bwrap AppArmor profile and installer on the affected Ubuntu host
status: todo
type: task
priority: high
created_at: 2026-09-04T10:09:46Z
updated_at: 2026-09-04T10:09:46Z
---

The code for dotfiles-dist landed verified only by eval, shellcheck and `nix flake check` on darwin. Two verification steps require real Linux hosts and are still outstanding.

## Why this matters

The wrapper now gates **every** codex invocation on Linux behind the bwrap probe and exits 1 on failure, so a probe that misbehaves on some Linux host breaks codex there. One bug of exactly that class was already caught in review (the probe originally exec'd `/bin/true`, which does not exist on NixOS, whose `/bin` holds only `sh`).

The highest-risk unverified assumption is the profile's **omitted `abi` pragma**. Ubuntu's own userns profiles all carry `abi <abi/4.0>,`. Omitting it should make apparmor_parser warn and fall back to the running kernel's feature set — but if it instead pins a lower feature abi, `userns` is silently dropped and the profile loads granting nothing. The installer's final re-probe catches this loudly, so the blast radius is "the fix doesn't work" rather than "it silently doesn't work".

## Todo

- [ ] On a healthy Linux host (no AppArmor userns restriction), confirm the probe has no false positives: `nix shell nixpkgs#bubblewrap nixpkgs#coreutils -c bwrap --unshare-user --ro-bind / / "$(command -v true)"` → exit 0.
- [ ] On NixOS specifically, confirm the probe passes and codex still starts — this is the regression the `/bin/true` fix addressed.
- [ ] On the affected Ubuntu host: `apparmor_parser -Q` the profile as a non-root user and confirm it parses.
- [ ] Confirm the unprivileged preflight checks read correctly as a non-root user: `[ -d /sys/kernel/security/apparmor ]` must not false-negative if securityfs is root-traversable there.
- [ ] Confirm codex refuses to start with the actionable message rather than failing mid-session.
- [ ] `codex-apparmor-setup --dry-run` prints the plan and changes nothing.
- [ ] `codex-apparmor-setup` installs and reloads; check its stderr and `sudo aa-status | grep nix-bwrap` to settle the `abi` question. Add `abi <abi/4.0>,` to the profile if userns is not actually granted.
- [ ] codex now starts and a sandboxed edit succeeds where it previously failed with `bwrap: loopback: Failed RTM_NEWADDR`.
- [ ] Re-running `codex-apparmor-setup` exits 0 without prompting for sudo.
- [ ] Confirm the Landlock alternative still works: `codex sandbox -c features.use_legacy_landlock=true -- /bin/true`. This also confirms `features.use_legacy_landlock` is the correct config key — a wrong key passed via `-c` is likely silently ignored.
