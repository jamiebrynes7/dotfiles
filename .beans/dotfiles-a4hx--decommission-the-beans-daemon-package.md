---
# dotfiles-a4hx
title: Decommission the beans-daemon package
status: completed
type: task
priority: normal
created_at: 2026-11-13T14:26:59Z
updated_at: 2026-11-13T14:36:58Z
---

**Spec:** none — decisions agreed in conversation are recorded under Notes.

## What to build

Retire the beans daemon end to end. No host can enable it any more, the flake stops building and checking it, and the docs stop describing it. The repo keeps its Rust scaffolding (toolchain, crane wiring, `rust-*` checks, the `cargo fmt` pre-commit gate, and the local-Rust-binary build helper), so a future crate can be added without rebuilding that plumbing.

## Acceptance criteria

- [x] `pkgs.dotfiles.beans-daemon` no longer exists, and `nix flake show` lists no `beans-daemon` package or check on either system
- [x] The `beansd`, `beansctl` and `beansd-rpc` crates are gone from the workspace, and the lockfile has no entries left that only they used
- [x] The `dotfiles.programs.beans-daemon` option is gone: setting it fails evaluation with home-manager's standard unknown-option error
- [x] `nix flake check` passes on both systems with the Rust workspace empty, including the `rust-fmt`, `rust-clippy` and `rust-test` checks, or with those checks skipped while the workspace has no members
- [x] The devShell still provides the Rust toolchain, and the pre-commit hook still runs `cargo fmt --check` when `.rs` files are staged
- [x] The root `CLAUDE.md` and `crates/CLAUDE.md` no longer describe beansd, beansctl, beansd-rpc, the `--dev` instance or the daemon package. `crates/CLAUDE.md` describes an empty workspace kept ready for future crates, and the commit-scope examples in the root `CLAUDE.md` no longer name the deleted crates
- [x] Open bean dotfiles-4o6t (beansd rust-embed) is scrapped, with a Reasons for Scrapping section that points at this decommission

## Constraints

- `beans-serve` stays in the beans package. People still run it by hand.
- The `beans` CLI program module and its Claude Code integration are unchanged.
- The specs under `docs/specs/` stay as they are. They are point-in-time records (see the Specs convention in the root `CLAUDE.md`).
- The deleted option gets no `mkRemovedOptionModule` stub. Delete it outright.

## Notes

- Risk: crane's deps-only build, clippy and nextest may refuse a virtual workspace that has no members. If they do, gate the Rust checks (and the shared deps artifact) on the workspace having members, rather than adding a placeholder crate.
- Live machines: home-manager removes the launchd agent or systemd user service when it switches. The `beans-daemon` config dir, log and socket are left behind. Mention this in the PR so they can be deleted by hand; don't automate it.

## Summary of Changes

- Deleted the beansd, beansctl and beansd-rpc crates, the beans-daemon package and the `dotfiles.programs.beans-daemon` home-manager module. The launchd/systemd service and zsh chpwd hook went with it.
- Trimmed the root Cargo.toml's daemon-only workspace deps and emptied Cargo.lock.
- Kept the Rust scaffolding. Cargo rejects a member-less workspace, so crates/default.nix now gates the `rust-*` checks on `hasCrates` (some `crates/<name>/Cargo.toml` exists).
- Rewrote crates/CLAUDE.md for an empty, ready workspace, and removed daemon references from the root CLAUDE.md.
- Scrapped dotfiles-4o6t.
- Verified: `nix flake check` (darwin) and `--all-systems --no-build` pass, neither system lists a beans-daemon or rust-* check, and setting the old option fails with the unknown-option error.
