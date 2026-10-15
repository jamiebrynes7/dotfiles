---
# dotfiles-ltuq
title: paseo home-manager module
status: scrapped
type: feature
priority: normal
created_at: 2026-08-19T10:54:38Z
updated_at: 2026-10-15T10:00:58Z
parent: dotfiles-7043
---

The module itself: `home/programs/paseo.nix`, auto-imported by `home/default.nix`.

Owns the whole option surface (`enable`, `package`, `dataDir`, `listenAddress`, `port`, `hostnames`, `allowAnyHostname`, `password`, `passwordFile`, `environment`, `extraPath`), the shared launcher script, and both service definitions (`systemd.user.services.paseo` on Linux, `launchd.agents.paseo` on macOS).

Not wired into any profile in `home/profiles.nix` — opt-in per host.

Tasks in this feature are TDD against the `paseo-module` flake check, which the first task introduces alongside the module skeleton. Each subsequent task extends the check's scratch config first, watches it fail, then implements.

## Reasons for Scrapping

Superseded. This work landed through a different route under dotfiles-ajpl (e6a50de, "packages/paseo: vendor paseo and add a home-manager module"). paseo comes from `packages/paseo`, which `callPackage`s upstream's `nix/package.nix` out of a `fetchFromGitHub` source. There is no flake input, no `overlays/` directory and no v0.3.1 pin. `home/programs/paseo.nix` already carries `hostnames`, `extraPath`, `environment` and `environmentCommand`, and later the plugins option (dotfiles-5nj7). Nothing in this plan is left to build against the current code.
