---
# dotfiles-qety
title: Build only the flake checks a PR changes
status: completed
type: task
priority: normal
created_at: 2026-11-04T15:57:46Z
updated_at: 2026-11-04T16:50:43Z
---

CI runs `nix flake check` on every PR, including ones that only touch `.beans/`, `docs/` or CLAUDE.md/README files, none of which Nix evaluates. Skip the expensive steps for those while keeping the required `flake-check` status reporting.

Approach changed from a changed-paths regex to diffing derivations: evaluate `checks` at the PR's base and head, build only the checks whose drvPath differs. Exact, and nothing to keep in sync with what the flake reads.

- [x] PRs: `nix flake check --no-build`, then build only changed checks
- [x] Fail closed: if the base can't be evaluated, build every check
- [x] Pushes to master keep the full `nix flake check`
- [x] Update CLAUDE.md's description of what CI runs
- [x] Post (and edit in place) a PR comment listing which checks were built
- [x] `workflow_dispatch` runs the full check on any branch (replaces a short-lived `CI_FULL_FLAKE_CHECK` variable)

## Summary of Changes

`.github/workflows/ci.yml`: PRs evaluate `checks.<system>` drvPaths at the base (merge commit's first parent) and head, run `nix flake check --no-build`, and build only checks whose drvPath differs; an unevaluable base builds everything. The drvPath eval runs before `--no-build` because packages/paseo is IFD and `--no-build` cannot fetch it on a cold store (this broke the first CI run). A single PR comment, edited in place, lists the built checks. Pushes to master and `workflow_dispatch` keep the full check. A docs-only PR now takes ~30s instead of ~12 min.

Tried and dropped along the way: a changed-paths regex (missed `.nix` files under docs/ that the nixfmt check formats, and renames out of home/), and a `CI_FULL_FLAKE_CHECK` repo variable (superseded by `workflow_dispatch`).
