---
# dotfiles-ajpl
title: Add paseo home-manager module
status: completed
type: feature
priority: normal
created_at: 2026-08-31T17:40:36Z
updated_at: 2026-08-31T17:53:14Z
---

Vendor paseo (daemon from source, macOS desktop app from the signed release zip) and expose it as a home-manager module with an opt-in user service. Plan: ~/.claude/plans/i-want-to-include-peppy-yeti.md

## Todo

- [x] packages/paseo/update.sh
- [x] packages/paseo/hashes.json (pinned to 0.6.1; v0.7.0 has no assets yet)
- [x] packages/paseo/default.nix
- [x] packages/paseo/desktop.nix
- [x] home/programs/paseo.nix
- [x] flake.nix: mac-app-util input + thread inputs into ./home
- [x] home/default.nix: import mac-app-util (startServices dropped: HM 26.05 already defaults to sd-switch)
- [x] CLAUDE.md: document the vendored-source package shape
- [x] Verify: nix build .#paseo-desktop, nix build .#paseo, nix flake check (all pass on darwin)

## Summary of Changes

- `packages/paseo/` — daemon vendored as source: `fetchFromGitHub` the release tag, then `callPackage` upstream `nix/package.nix` with our nixpkgs. First IFD package in the repo (marked in-code). `hashes.json` records version, tag, src hash, our own `npmDepsHash`, and the signed macOS zip hash. `update.sh` computes the npm hash via `nix shell --inputs-from` so it matches our nixpkgs, reads the desktop hash from `latest-mac.yml` (no 146MB nightly download), guards against an unfixed lockfile, and exits 0 both when the version is unchanged and when a tag has no assets yet.
- `packages/paseo/desktop.nix` — `passthru.desktop`, a plain fetch+unzip of upstream signed/notarized `Paseo.app`. `dontFixup` preserves the signature; verified `spctl` reports "accepted, source=Notarized Developer ID". Aliased as `packages.aarch64-darwin.paseo-desktop` because Nix will not traverse a derivation passthru from a flake output path.
- `home/programs/paseo.nix` — `dotfiles.programs.paseo`. `enable` (daemon pkg) / `service.enable` (launchd agent or systemd user unit) / `desktop.enable` are independent, so a Mac wanting only the app builds nothing. Service PATH includes `~/.local/bin` by default, which is the whole reason the upstream NixOS module needed a mkForce on warbird. Relay is not exposed at all; the server always gets `--no-relay`. `settings` writes `config.json` via `home.file` (safe: the daemon only writes it when absent and its chmod is best-effort); unset by default so the daemon owns the file and `set-password` works.
- `flake.nix` / `home/default.nix` — `mac-app-util` input (darwin-only, inert on Linux) for stable-path `.app` trampolines; `inputs` threaded into `./home`.
- `CLAUDE.md` — documents the vendored-source package shape, the IFD, and the new `update.sh` exit-0-on-missing-assets rule.

Verified on darwin: `nix build .#paseo`, `nix build .#paseo-desktop`, `nix flake check`, daemon smoke test (status reports `Relay: disabled`, creates its own 0600 config.json, graceful SIGTERM). Linux derivation instantiates; the Linux *build* is unverified locally and CI is its first real test.

Deliberately out of scope: migrating `sys-warbird` and `sys-defiant` onto the module.
