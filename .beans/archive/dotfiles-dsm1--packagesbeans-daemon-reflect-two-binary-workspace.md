---
# dotfiles-dsm1
title: 'packages/beans-daemon: reflect two-binary workspace (beansd + beansctl)'
status: completed
type: task
priority: normal
created_at: 2026-05-16T07:47:28Z
updated_at: 2026-05-16T08:14:06Z
parent: dotfiles-qwfb
---

The workspace split landed `beansctl` as a new binary alongside `beansd`, but `packages/beans-daemon/default.nix` still describes itself as a single-binary daemon package:

- `pname = "beans-daemon"` — generic; doesn't reflect the two-binary output
- `mainProgram = "beansd"` — correct for `nix run`, but hides `beansctl` from discovery
- Path lives at `packages/beans-daemon/` while the crates moved to `crates/` (cosmetic mismatch)

`buildRustPackage` with `cargoBuildFlags = [ "--workspace" ]` does install both binaries into `$out/bin`, so consumers technically get `beansctl` for free — but the framing is wrong and there's no signal that two binaries exist.

**Decisions to make:**

- [x] Keep one derivation that exposes both binaries — chose this. Kept `pname = "beans-daemon"` (downstream system repos may reference the attribute name); added an inline comment + updated `meta.description` so the two-binary output is explicit.
- [ ] ~~Or split into two derivations~~ — deferred. One bundled derivation is the simpler default; can revisit when there's a real need for CLI-only installs.
- [ ] ~~Move `packages/beans-daemon/` → `packages/beans/`~~ — declined. `packages/beans/` is already used by the upstream `hmans/beans` Go package. No clean rename target.
- [ ] ~~Update `flake.nix:62`~~ — N/A; no rename.

**Acceptance:**

- [x] `nix flake check` passes (exit 0). A pre-existing test-fixture flake in the supervisor's port-binding tests can occasionally surface as `EADDRINUSE` in the sandbox; rebuilds succeed. Tracked in `dotfiles-ls8b`.
- [x] `beansd --help` from the nix-built `$out/bin/beansd` works (mainProgram routes `nix run` here).
- [x] `beansctl --help` from the same nix-built `$out/bin/beansctl` works.
- [x] No `templates/systems/**` consumes `dotfiles.beans-daemon` (grep confirmed). Downstream system repos created from these templates aren't impacted by metadata-only changes.

## Summary of Changes

- `packages/beans-daemon/default.nix` — added an inline comment near `cargoBuildFlags = [ "--workspace" ]` documenting that the workspace produces both `beansd` (mainProgram) and `beansctl`, and updated `meta.description` to name both binaries explicitly. `pname` and directory layout unchanged.
- Verified `nix build .#beans-daemon` succeeds and `$out/bin/{beansd,beansctl}` both respond to `--help`.
- A pre-existing test flake (`supervisor` + `handler` tests racing on loopback ephemeral ports) was uncovered while validating `nix flake check`. It's a test-fixture issue, benign in production. Filed as `dotfiles-ls8b` for the proper fix (inject a `HealthChecker` seam so the tests don't bind real ports).
