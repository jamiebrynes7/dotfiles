---
# dotfiles-qety
title: Build only the flake checks a PR changes
status: in-progress
type: task
priority: normal
created_at: 2026-11-04T15:57:46Z
updated_at: 2026-11-04T16:42:08Z
---

CI runs `nix flake check` on every PR, including ones that only touch `.beans/`, `docs/` or CLAUDE.md/README files, none of which Nix evaluates. Skip the expensive steps for those while keeping the required `flake-check` status reporting.

Approach changed from a changed-paths regex to diffing derivations: evaluate `checks` at the PR's base and head, build only the checks whose drvPath differs. Exact, and nothing to keep in sync with what the flake reads.

- [x] PRs: `nix flake check --no-build`, then build only changed checks
- [x] Fail closed: if the base can't be evaluated, build every check
- [x] Pushes to master keep the full `nix flake check`
- [x] Update CLAUDE.md's description of what CI runs
- [x] Post (and edit in place) a PR comment listing which checks were built
- [x] `workflow_dispatch` runs the full check on any branch (replaces a short-lived `CI_FULL_FLAKE_CHECK` variable)
