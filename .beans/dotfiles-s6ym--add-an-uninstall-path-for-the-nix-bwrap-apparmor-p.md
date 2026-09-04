---
# dotfiles-s6ym
title: Add an uninstall path for the nix-bwrap AppArmor profile
status: todo
type: task
priority: low
created_at: 2026-09-04T10:09:56Z
updated_at: 2026-09-04T10:09:56Z
---

From the review of dotfiles-dist.

Once `codex-apparmor-setup` writes `/etc/apparmor.d/nix-bwrap` it is permanent root-owned host state. There is no `--remove`, and nothing reverses it if `dotfiles.programs.codex.enable` goes false — home-manager cannot clean up state it never owned.

## Todo

- [ ] Add `codex-apparmor-setup --remove`: unload the profile (`apparmor_parser -R`), delete `/etc/apparmor.d/nix-bwrap`, re-probe and report the resulting state.
- [ ] Document it wherever the setup command is surfaced.
