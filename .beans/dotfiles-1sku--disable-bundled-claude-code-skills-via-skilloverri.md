---
# dotfiles-1sku
title: Disable bundled Claude Code skills via skillOverrides
status: completed
type: task
priority: normal
created_at: 2026-05-09T12:31:42Z
updated_at: 2026-05-09T12:42:56Z
---

Add a `skillOverrides` map to the Nix-managed `~/.claude/settings.json` so unwanted bundled Claude Code skills are hidden from Claude's context and/or the `/` menu.

## Background

Claude Code ships a set of bundled skills (e.g. `/simplify`, `/batch`, `/debug`, `/loop`, `/claude-api`, `/init`, `/review`, `/security-review`). They're always listed unless overridden, which costs description tokens and clutters the `/` menu.

Docs: https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings

The `skillOverrides` setting takes one entry per skill, with one of four values:

| Value                 | Listed to Claude     | In `/` menu |
| --------------------- | -------------------- | ----------- |
| `on`                  | Name and description | Yes         |
| `name-only`           | Name only            | Yes         |
| `user-invocable-only` | Hidden               | Yes         |
| `off`                 | Hidden               | Hidden      |

Plugin skills are not affected.

## Where the change goes

`home/programs/claude-code/default.nix`, in the `settingsJson` attrset (currently lines 21–28). Mirror the existing `permissions` pattern: expose a `skillOverrides` option on `dotfiles.programs.claude-code`, default `{}`, and merge it into `settingsJson` only when non-empty.

Note: the docs say the `/skills` menu writes to `.claude/settings.local.json`, which is gitignored and stomped by home-manager's symlink to `settings.json` — declaring overrides in Nix is the right path.

## TODO

- [x] Add `skillOverrides` option to `dotfiles.programs.claude-code` (attrset of skill name → enum-ish string)
- [x] Wire it into `settingsJson` (only emit the key when the attrset is non-empty)
- [x] Decide which bundled skills to override, and to what value — candidates: `simplify`, `batch`, `debug`, `loop`, `claude-api`, `init`, `review`, `security-review`
- [x] Set the chosen overrides in the `config` block alongside `permissions`
- [x] `nix flake check --impure` to validate
- [x] Switch the system and confirm in `/skills` that hidden skills no longer appear (manual, post-merge)

## Implementation notes

- Added a `skillOverrides` option to `dotfiles.programs.claude-code` in `home/programs/claude-code/default.nix`. Type is `attrsOf (enum [ "on" "name-only" "user-invocable-only" "off" ])`, default `{}`.
- Merged into `settingsJson` via `lib.optionalAttrs` so the key is omitted when empty.
- Set the following bundled skills to `"off"` (hidden from Claude and the `/` menu): `claude-api`, `fewer-permission-prompts`, `init`, `keybindings-help`, `loop`, `review`, `schedule`, `security-review`, `update-config`. `simplify` deliberately left at default `"on"`.
- `nix flake check --impure` passes.
- Last unchecked TODO is a post-merge user step (system switch + `/skills` visual confirmation).
