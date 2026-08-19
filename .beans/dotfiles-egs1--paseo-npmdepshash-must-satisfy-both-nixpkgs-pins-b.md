---
# dotfiles-egs1
title: paseo npmDepsHash must satisfy both nixpkgs pins, but CI only checks linux
status: todo
type: task
created_at: 2026-08-19T12:44:49Z
updated_at: 2026-08-19T12:44:49Z
parent: dotfiles-pg0j
---

Raised during review of `dotfiles-l710` (the `paseo` flake input). Not a defect in
that diff — a design gap to resolve while implementing `dotfiles-rdkr`
(`overlays/paseo.nix`).

## The gap

This repo carries **two** nixpkgs pins:

- `inputs.nixpkgs` — `nixos-26.05`, used by `nixOsPkgs`
- `inputs.nixpkgs-darwin` — `nixpkgs-26.05-darwin`, used by `nixDarwinPkgs` (`flake.nix`)

`overlays/paseo.nix` will build paseo via `final.callPackage`, so
`pkgs.dotfiles.paseo` is built against **whichever nixpkgs `final` came from** — a
different revision per platform. A single hardcoded `npmDepsHash` must therefore be
valid under *both* pins.

Note the input's `inputs.nixpkgs.follows = "nixpkgs"` does **not** control this: the
overlay consumes `inputs.paseo` as a source tree (`"${inputs.paseo}/nix/package.nix"`),
so paseo's own flake outputs never evaluate. The follows only keeps a second `nixpkgs`
node out of `flake.lock`.

## Why it matters

`.github/workflows/ci.yml` runs `nix flake check` on `ubuntu-latest` only, so **just the
linux/`nixpkgs` build is ever exercised in CI** — while the machine that actually runs
paseo is darwin. Failure mode: green CI, then a local darwin `nix flake check` failing on
a hash mismatch after a routine `nix flake update` moves the two pins independently.

This also qualifies the epic's claim that landing at `pkgs.dotfiles.paseo` pulls paseo
into `checks.*` so "`nix flake check` builds it — the only thing that catches a stale
hash". True for one platform, not both.

Both pins are on the same 26.05 branch, so `prefetch-npm-deps` is very likely
byte-identical today — this is low-probability, not hypothetical-impossible. Nothing in
the design *ensures* it.

## Options to weigh

- [ ] Confirm empirically whether the hash differs across the two pins (build
      `pkgs.dotfiles.paseo` under both `nixOsPkgs` and `nixDarwinPkgs`).
- [ ] Decide the resolution: accept and document the risk in `overlays/paseo.nix`; or add
      a darwin runner to CI; or pin paseo's build to one nixpkgs explicitly so the hash
      has a single owner.
- [ ] Record the outcome as a comment in `overlays/paseo.nix` next to `npmDepsHash`, so
      the next person bumping the pin knows which platforms the hash was verified against.
