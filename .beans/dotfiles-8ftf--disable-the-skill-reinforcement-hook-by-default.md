---
# dotfiles-8ftf
title: Disable the skill-reinforcement hook by default
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:32:11Z
updated_at: 2026-08-15T15:53:59Z
parent: dotfiles-nj63
---

**File:** `home/programs/claude-code/hooks/skill-reinforcement.nix:45`

The hook injects a MANDATORY SKILL ACTIVATION SEQUENCE on every `UserPromptSubmit`, forcing a YES/NO verdict on every available skill before any work starts. It duplicates skill selection the harness now does natively from the `description` field, and it costs a wall of "NO — not relevant" reasoning every single turn.

Disable rather than delete, so it is one line from returning if skill discovery under-fires. The mechanism already exists: `hookType.enable` (`hooks/types.nix:41`) is an `mkEnableOption` defaulting to false, and `mergeHooks` (line 64) filters disabled hooks out of `settings.json`.

- [x] Change `enable = true;` to `mkDefault false` (unqualified, matching the file's `with lib;` style)
- [x] Confirm `lib` is in scope in the module args (it is via `with lib;` — use `mkDefault` consistently with the file style)
- [x] Run `nix flake check`
- [x] Verify the rendered `settings.json` for a test build no longer lists the skill-reinforcement command under `UserPromptSubmit`

Re-enable downstream with `dotfiles.programs.claude-code.hooks.skill-reinforcement.enable = true;`.

## Summary of Changes

`home/programs/claude-code/hooks/skill-reinforcement.nix:45` — `enable = true` → `enable = mkDefault false`.

The hook definition is retained in full; only its default flips. `mergeHooks` (`hooks/types.nix:64`) filters disabled hooks out of the generated `settings.json`, so nothing renders under `UserPromptSubmit`.

Verified by evaluating `mergeHooks` both ways: disabled yields `{ }` (no `UserPromptSubmit` key at all), enabled yields the hook entry. A subagent review additionally confirmed end-to-end through `mkHomeManagerSystem` that a host setting `dotfiles.programs.claude-code.hooks.skill-reinforcement.enable = true;` overrides the default and re-renders the hook — `mkDefault` (priority 1000) beats `mkEnableOption`'s 1500 and loses to a host's 100, and the enclosing `mkIf cfg.enable` preserves the inner priority modifier. A plain `enable = false;` would instead collide at priority 100 and fail evaluation, so `mkDefault` is load-bearing.

`nix flake check` passes.

Review notes: an intermediate revision added an explanatory comment above the option and corrected a now-false line in `docs/specs/2026-08-02-agent-plugins.md`. Both were reverted on user review — the comment was an artifact of the change itself, and the spec is a dated historical design artifact rather than living documentation. The rationale lives here and in the commit message instead.
