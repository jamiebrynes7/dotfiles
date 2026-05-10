---
# dotfiles-7zn7
title: Workspace skeleton — move single crate into crates/beansd/
status: completed
type: task
priority: normal
created_at: 2026-05-10T14:55:04Z
updated_at: 2026-05-10T16:00:02Z
parent: dotfiles-qwfb
---

**Files:**
- Create: `Cargo.toml` (workspace root)
- Move: `packages/beans-daemon/src/` → `crates/beansd/src/`
- Move: `packages/beans-daemon/static/` → `crates/beansd/static/`
- Move: `packages/beans-daemon/templates/` → `crates/beansd/templates/`
- Move: `packages/beans-daemon/Cargo.toml` → `crates/beansd/Cargo.toml` (rename `package.name` from `beans-daemon` to `beansd`)
- Move: `packages/beans-daemon/Cargo.lock` → `Cargo.lock` (workspace lock at repo root)
- Modify: `packages/beans-daemon/default.nix` (use `lib.fileset.toSource`)

No API changes. Pure restructuring. All 61 existing tests must still pass.

- [x] **Step 1: Create root `Cargo.toml`**

Write `Cargo.toml` at repo root:

```toml
[workspace]
members = ["crates/*"]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"

[workspace.dependencies]
anyhow = "1"
async-trait = "0.1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
```

- [x] **Step 2: Move the existing crate to `crates/beansd/`**

```bash
mkdir -p crates
git mv packages/beans-daemon/src crates/beansd/src
git mv packages/beans-daemon/static crates/beansd/static
git mv packages/beans-daemon/templates crates/beansd/templates
git mv packages/beans-daemon/Cargo.toml crates/beansd/Cargo.toml
git mv packages/beans-daemon/Cargo.lock Cargo.lock
```

- [x] **Step 3: Rewrite `crates/beansd/Cargo.toml`**

Replace contents (rename package, switch shared deps to `{ workspace = true }`):

```toml
[package]
name = "beansd"
version.workspace = true
edition.workspace = true

[[bin]]
name = "beansd"
path = "src/main.rs"

[dependencies]
anyhow.workspace = true
askama = "0.12"
async-trait.workspace = true
axum = { version = "0.7", features = ["macros"] }
clap = { version = "4", features = ["derive"] }
nix = { version = "0.29", features = ["signal"] }
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls"] }
serde.workspace = true
serde_json.workspace = true
thiserror = "1"
tokio.workspace = true
tokio-util = { version = "0.7", features = ["codec"] }
toml = "0.8"
tracing.workspace = true
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
xdg = "2"

[dev-dependencies]
assert_matches = "1"
tempfile = "3"
tower = { version = "0.4", features = ["util"] }
```

- [x] **Step 4: Rewrite `packages/beans-daemon/default.nix`**

Replace contents (filtered source via `lib.fileset.toSource` so unrelated repo edits don't trigger rebuilds):

```nix
{ lib, rustPlatform }:

let
  root = ../..;
  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/Cargo.toml")
      (root + "/Cargo.lock")
      (root + "/crates")
    ];
  };
in
rustPlatform.buildRustPackage {
  pname = "beans-daemon";
  version = "0.1.0";
  inherit src;
  cargoLock.lockFile = root + "/Cargo.lock";
  cargoBuildFlags = [ "--workspace" ];
  meta = with lib; {
    description = "Background daemon for the beans issue tracker";
    mainProgram = "beansd";
    license = licenses.mit;
  };
}
```

- [x] **Step 5: Run the full workspace test suite**

```bash
nix develop --command cargo test --manifest-path Cargo.toml --workspace
```

Expected: 61 tests pass.

- [x] **Step 6: Verify the Nix derivation builds**

```bash
nix flake check
```

Expected: success.

- [x] **Step 7: Commit**

```bash
git add Cargo.toml Cargo.lock crates/ packages/beans-daemon/default.nix
git commit -m "packages/beans-daemon: introduce workspace, move crate to crates/beansd/"
```

## Summary of Changes

Introduced a Cargo workspace at the repo root and moved the single `beans-daemon` crate to `crates/beansd/` (binary still named `beansd`). Workspace-shared deps (anyhow, async-trait, serde, serde_json, tokio, tracing) are declared once in the root `Cargo.toml`. `packages/beans-daemon/default.nix` now consumes a filtered `lib.fileset.toSource` covering only `Cargo.toml`, `Cargo.lock`, and `crates/`, so unrelated repo edits no longer invalidate the derivation. Dropped the now-redundant `[package.metadata.askama] dirs = ["templates"]` (askama 0.12 looks under `templates/` by default).

Verified: `cargo test --workspace` → 61/61 pass. `nix flake check` → builds `beans-daemon-0.1.0.drv` clean.
