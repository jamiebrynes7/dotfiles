---
# dotfiles-60h5
title: Default approvals_reviewer to auto_review in codex module
status: completed
type: task
priority: normal
created_at: 2026-07-13T09:37:33Z
updated_at: 2026-07-13T09:38:29Z
---

Expose a configurable dotfiles.programs.codex.approvalsReviewer option (default "auto_review") that renders into a managed -c override in home/programs/codex/default.nix.

- [x] Add approvalsReviewer mkOption
- [x] Add approvals_reviewer entry to managedConfig
- [x] Update managedConfig comment to document string quoting
- [x] nixfmt + nix flake check

## Summary of Changes

Added a configurable `dotfiles.programs.codex.approvalsReviewer` option (type str, default `"auto_review"`) in `home/programs/codex/default.nix`, feeding a new `approvals_reviewer` entry in the `managedConfig` attrset. The value embeds its own TOML quotes so the wrapper injects `-c 'approvals_reviewer="auto_review"'`. Updated the `managedConfig` comment to document string-value quoting. Verified via `nix flake check` (all checks pass, incl. nixfmt) and by evaluating the rendered `-c` args.
