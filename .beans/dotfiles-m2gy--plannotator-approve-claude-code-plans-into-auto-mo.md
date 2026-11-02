---
# dotfiles-m2gy
title: 'plannotator: approve Claude Code plans into auto mode, not acceptEdits'
status: completed
type: task
priority: normal
created_at: 2026-11-02T10:46:21Z
updated_at: 2026-11-02T11:54:14Z
---

Plannotator's post-approval permission mode is a per-hostname browser cookie defaulting to acceptEdits; config.json has no key for it. Rewrite the hook's setMode acceptEdits -> auto in the claude-code hook command so approvals land in auto mode declaratively.

- [x] Wrap the claude-code PermissionRequest hook output through jq rewriting setMode acceptEdits -> auto
- [x] Verify the rewrite against sample allow/deny/non-JSON output
- [x] nix flake check passes

## Summary of Changes

The claude-code plan-review hook now pipes plannotator's output through a jq filter (home/programs/plannotator/default.nix) that rewrites a setMode of acceptEdits to auto, leaving other modes, denials and non-JSON lines untouched and preserving the exit code (pipefail). Codex's hook and direct CLI use are unaffected. Verified by building the real hook command against a stub plannotator; nix flake check passes. Upstream has no config.json key for the mode (it is a per-hostname cookie), so this can be dropped if one is added.
