---
# dotfiles-dsm1
title: 'packages/beans-daemon: reflect two-binary workspace (beansd + beansctl)'
status: todo
type: task
created_at: 2026-05-16T07:47:28Z
updated_at: 2026-05-16T07:47:28Z
parent: dotfiles-qwfb
---

The workspace split landed `beansctl` as a new binary alongside `beansd`, but `packages/beans-daemon/default.nix` still describes itself as a single-binary daemon package:

- `pname = "beans-daemon"` — generic; doesn't reflect the two-binary output
- `mainProgram = "beansd"` — correct for `nix run`, but hides `beansctl` from discovery
- Path lives at `packages/beans-daemon/` while the crates moved to `crates/` (cosmetic mismatch)

`buildRustPackage` with `cargoBuildFlags = [ "--workspace" ]` does install both binaries into `$out/bin`, so consumers technically get `beansctl` for free — but the framing is wrong and there's no signal that two binaries exist.

**Decisions to make:**

- [ ] Keep one derivation that exposes both binaries (low effort; rename pname → `beans` or `beansd-suite`; document that `beansctl` is also installed)
- [ ] Or split into two derivations (`beansd`, `beansctl`) sharing a common `buildPhase` via a helper — more typical Nix style, lets consumers install just the CLI on machines without a daemon
- [ ] Decide whether to also move `packages/beans-daemon/` → `packages/beans/` (or similar) for consistency with the new crate layout
- [ ] Update `flake.nix:62` (`packageArgs.beans-daemon`) if the package is renamed

**Acceptance:**

- [ ] `nix flake check` passes
- [ ] `nix run .#dotfiles.<name> -- --help` works for at least `beansd`
- [ ] `beansctl` is reachable from a built output (either same derivation or its own)
- [ ] Downstream system templates (`templates/systems/`) still build (or are flagged for update if they consume this package)
