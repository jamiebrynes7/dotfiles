---
# dotfiles-ltuq
title: paseo home-manager module
status: todo
type: feature
created_at: 2026-08-19T10:54:38Z
updated_at: 2026-08-19T10:54:38Z
parent: dotfiles-7043
---

The module itself: `home/programs/paseo.nix`, auto-imported by `home/default.nix`.

Owns the whole option surface (`enable`, `package`, `dataDir`, `listenAddress`, `port`, `hostnames`, `allowAnyHostname`, `password`, `passwordFile`, `environment`, `extraPath`), the shared launcher script, and both service definitions (`systemd.user.services.paseo` on Linux, `launchd.agents.paseo` on macOS).

Not wired into any profile in `home/profiles.nix` — opt-in per host.

Tasks in this feature are TDD against the `paseo-module` flake check, which the first task introduces alongside the module skeleton. Each subsequent task extends the check's scratch config first, watches it fail, then implements.
