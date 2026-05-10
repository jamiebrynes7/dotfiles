---
# dotfiles-fbq7
title: Write `packages/beans-daemon/default.nix` derivation
status: scrapped
type: task
priority: normal
created_at: 2026-05-03T14:42:39Z
updated_at: 2026-05-10T15:52:56Z
parent: dotfiles-lfly
---

**Files:**
- Create: `packages/beans-daemon/default.nix`
- Modify: `flake.nix` (add to `packages` output)

- [ ] **Step 1: Write the derivation**

`packages/beans-daemon/default.nix`:
```nix
{ lib, rustPlatform, pkg-config, openssl }:

rustPlatform.buildRustPackage rec {
  pname = "beans-daemon";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs       = [ openssl ];   # for reqwest's rustls-tls? not needed if rustls only — drop if unused

  # The launcher's static assets are include_bytes!'d at compile time,
  # so no separate asset install step is needed.

  meta = with lib; {
    description = "Per-user daemon multiplexing beans-serve across projects";
    license     = licenses.mit;
    mainProgram = "beansd";
  };
}
```

(If `cargo build` works without `openssl` because we only use `rustls-tls` features, drop `pkg-config` and `openssl` to keep the closure small.)

- [ ] **Step 2: Wire into flake outputs**

In `flake.nix`, find the `packages` output (or wherever per-system packages live) and add:
```nix
        beans-daemon = pkgs.callPackage ./packages/beans-daemon { };
```

- [ ] **Step 3: Build via Nix**

Run from the repo root: `nix build .#beans-daemon`
Expected: builds cleanly; produces `result/bin/beansd`.

- [ ] **Step 4: Smoke run from Nix output**

Run: `./result/bin/beansd --version`
Expected: `beansd 0.1.0`

- [ ] **Step 5: Commit**

```
git add packages/beans-daemon/default.nix flake.nix
git commit -m 'packages/beans-daemon: nix derivation'
```

## Reasons for Scrapping

Superseded by `dotfiles-qwfb` (Workspace split). The workspace-aware `default.nix` — `lib.fileset.toSource` filtered against the repo root, `cargoLock.lockFile = root + "/Cargo.lock"`, `cargoBuildFlags = [ "--workspace" ]` — is written as part of `dotfiles-7zn7` (Task 1: Workspace skeleton). The pre-workspace single-crate derivation this bean specced is no longer the right shape.
