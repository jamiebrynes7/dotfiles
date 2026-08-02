# Package agent skills as Claude Code skills-directory plugins

## Problem

`home/lib/ai/skills/default.nix` (`mkSkillFiles`) fans a flat list of skill
directories out to `~/.claude/skills`, `~/.cursor/skills` and `~/.codex/skills`,
filtering YAML frontmatter per variant at build time. Feature bundling exists only
informally: `home/programs/plannotator/default.nix` wires a skill *and* a hook by
hand, `home/programs/beans.nix` wires hooks *and* a permission entry by hand, and
neither can be toggled as a unit.

Two consequences motivate this work:

1. **No per-project control.** Home-manager only knows `$HOME`, so every skill and
   hook is on in every project. The beans `SessionStart`/`PreCompact` prime hooks
   fire in repositories that have no beans database.
2. **No bundle abstraction.** Adding a feature that spans a skill plus a hook plus
   an MCP server means editing three unrelated places per assistant.

Claude Code's **skills-directory plugins** solve both: any folder under a skills
directory containing `.claude-plugin/plugin.json` loads as `<name>@skills-dir` with
no marketplace, no install step, and discovery *in place* rather than a copy into
the plugin cache. Enablement resolves from `defaultEnabled` in the manifest,
overridable by an `enabledPlugins` entry at any settings scope — including a
project's `.claude/settings.local.json`.

## Goals

- Group skills, hooks and MCP servers into named plugins declared in one place.
- Enable and disable those plugins per project.
- Preserve every property the current setup has: build-time variant frontmatter
  filtering, Nix-store-pinned hook commands, eval-time conflict assertions, no
  network access, no interactive install step.

## Non-goals

- **Sharability.** Nothing here is installable by anyone else. A real
  `.claude-plugin/marketplace.json` can be layered on the same derivations later.
- **Codex and Cursor plugin packaging.** Both now have plugin formats
  (`.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`), but Cursor's
  local-install story is undocumented. They keep consuming the same declarations as
  today's loose skill fan-out.
- **Generalising `task-implementer`.** Tracked as a follow-up.

## Design

### Delivery mechanism

Each plugin is installed as `~/.claude/skills/df-<name>/` — the same parent
directory `mkSkillFiles` already targets — but as a plugin folder rather than a
bare skill folder:

```
~/.claude/skills/df-plannotator/
  .claude-plugin/plugin.json     { name, version, description, author, defaultEnabled }
  skills/<skill>/SKILL.md        variant-filtered, plus any supporting files
  hooks/hooks.json               emitted only when hooks are declared
```

Because discovery is in place, a `home-manager switch` that repoints the symlink is
live in the next session — no marketplace registration, no cache invalidation, no
trust prompt, and no new mutable state under `~/.claude/plugins/`.

Skills packaged inside a plugin are namespaced by plugin name: `brainstorming`
becomes `df-base:brainstorming`. This is accepted, not worked around.

### Nix surface

New option namespace `dotfiles.ai.plugins.<name>`, declared in
`home/lib/ai/plugins/module.nix` and imported explicitly from the `imports` list in
`home/default.nix` (it is infrastructure, not a program, so it does not go in the
auto-discovered `home/programs/` scan):

```nix
dotfiles.ai.plugins.plannotator = {
  enable = true;
  description = "Plan and code review via plannotator";
  version = "0.1.0";
  defaultEnabled = true;
  skillDirs = [ ./skills ];
  hooks.plannotator-review = {
    enable = true;
    event = "PermissionRequest";
    matcher = "ExitPlanMode";
    hooks = [
      { type = "command"; command = "${plannotatorWrapper}/bin/plannotator"; timeout = 345600; }
    ];
  };
};
```

Option types:

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | `false` | Whether the plugin is emitted at all |
| `description` | str | — | Required; written to `plugin.json` |
| `version` | str | `"0.1.0"` | Written to `plugin.json` |
| `defaultEnabled` | bool | `true` | Written to `plugin.json`; the global default |

`author` is written by the renderer as a constant, not an option — `claude plugin
validate` warns when it is absent.
| `skillDirs` | listOf path | `[ ]` | Directories of `<skill>/SKILL.md` subdirectories |
| `hooks` | attrsOf hookType | `{ }` | Reuses `home/programs/claude-code/hooks/types.nix` |

Plugins can also carry MCP servers, agents, commands and output styles. None of the
three plugins below declares any, so those options are deliberately left out of this
change and added when a consumer exists.

The attribute key is the short name (`plannotator`); the `df-` prefix is
applied once at render time so the on-disk name and the `enabledPlugins` id cannot
drift from each other.

`hookType` and `mergeHooks` move from `home/programs/claude-code/hooks/types.nix`
to `home/lib/ai/plugins/` so the plugin library does not depend on a program module;
the claude-code module imports them from the new location for its own module-level
hooks. The move is mechanical — no schema changes.

### Renderer

`home/lib/ai/plugins/default.nix`, sibling to `skills/default.nix`, reusing the
existing `processFrontmatter` tool and the `readSkillDir` helper (lifted from
`skills/default.nix` into a shared spot so both call the same implementation).

`mkPluginFiles { variant, targetDir, plugins }` returns `{ files, conflicts }`:

- One `pkgs.runCommand` derivation per enabled plugin, laid out as above. Skills are
  copied and their `SKILL.md` overwritten with the variant-filtered version, exactly
  as `processSkill` does today.
- `hooks/hooks.json` is `{ hooks = mergeHooks cfg.hooks; }`, the same shape the
  claude-code module writes into `settings.json` today.
- `files` maps `"${targetDir}/df-${name}"` to the derivation with
  `recursive = true`.
- `conflicts` lists skill names that collide *within* a single plugin. Cross-plugin
  collisions are harmless under Claude Code namespacing.

### Assistant projections

| Assistant | Consumes | Result |
|---|---|---|
| Claude Code | `mkPluginFiles { variant = "cc"; targetDir = ".claude/skills"; }` | Plugin folders |
| Codex | `mkSkillFiles` over `lib.concatMap (p: p.skillDirs)` of enabled plugins | Today's loose skills, unchanged |
| Cursor | same as Codex, `variant = "cursor"` | Today's loose skills, unchanged |

Codex and Cursor flatten, so their existing cross-directory skill-name conflict
assertion is kept as-is for them. The per-assistant `skillsDirs` options are removed
from all three modules; `dotfiles.ai.plugins` is the only entry point.

A new `dotfiles.programs.claude-code.enabledPlugins` option (`attrsOf bool`, default
`{ }`) writes `enabledPlugins` into the generated `~/.claude/settings.json` for
forcing a plugin on or off globally. It stays empty by default: `defaultEnabled` in
each manifest carries the global default, so per-project settings remain the only
thing that has to be edited by hand.

### Plugin inventory

| Plugin | Contents | `defaultEnabled` |
|---|---|---|
| `df-base` | the 10 skills in `home/lib/ai/skills/` + the `skill-reinforcement` `UserPromptSubmit` hook | `true` |
| `df-plannotator` | the `plannotator-user-code-review` skill + the `PermissionRequest`/`ExitPlanMode` hook | `true` |
| `df-beans` | the `SessionStart` and `PreCompact` `beans prime` hooks | `false` |

Notes on the inventory:

- `skill-reinforcement` moves from `home/programs/claude-code/hooks/skill-reinforcement.nix`
  into `df-base`, so it toggles with the skills it reinforces. Today it is
  unconditional.
- `df-beans` carries hooks only. `task-implementer` and `whats-next` stay in
  this repository's `.claude/skills/`, because `whats-next` hands off to
  `task-implementer` and shipping one without the other would break that handoff in
  other repositories. They move into the plugin once `task-implementer` is
  generalised (follow-up).
- The `Bash(beans *)` permission entry stays in `home/programs/beans.nix` — plugins
  cannot carry a permission allowlist. It is inert when the plugin is off.
- `cship`'s statusline and the `debug` hook stay module-level; neither is plugin
  content.
- `home/lib/ai/global-instructions.md` and the `skillOverrides` mechanism for muting
  Anthropic's built-in skills are unchanged.

Because `df-beans` is `defaultEnabled: false`, this repository commits its own
opt-in to `.claude/settings.json`:

```json
{ "enabledPlugins": { "df-beans@skills-dir": true } }
```

### Migration

1. Add `home/lib/ai/plugins/` (module + renderer); move `hookType`/`mergeHooks`
   into it.
2. Declare `df-base` in the plugins module itself, sourcing
   `aiSkills.builtinSkillsDir`; delete `skill-reinforcement.nix`'s module wiring and
   fold its hook into the plugin.
3. Convert `home/programs/plannotator/default.nix`: replace its
   `claude-code.skillsDirs` and `claude-code.hooks.plannotator-review` wiring with a
   single `dotfiles.ai.plugins.plannotator` block. Its Codex hook stays where it is —
   the events differ per assistant (`Stop` vs `PermissionRequest`), so it is not
   plugin content under this design.
4. Convert `home/programs/beans.nix`: prime hooks move into
   `dotfiles.ai.plugins.beans`; the permission entry stays.
5. Rewire claude-code, codex and cursor modules to consume `dotfiles.ai.plugins`;
   remove their `skillsDirs` options.
6. Commit `.claude/settings.json` in this repository enabling `df-beans@skills-dir`.
7. Update `home/lib/ai/CLAUDE.md` and the root `CLAUDE.md` structure section.

## Validation

The three assumptions the design rests on were verified against a hand-written
plugin folder before planning, using Claude Code 2.1.220 (`defaultEnabled` requires
2.1.154) and a scratch `HOME`. All three hold:

1. **Symlinked-file plugin trees are discovered.** A plugin laid out as real
   directories containing symlinks to a read-only source — the exact shape
   home-manager produces with `recursive = true` — is found, including a symlinked
   `.claude-plugin/plugin.json`. `claude plugin list` reports it under
   "Skills-directory plugins (.claude/skills/*)" with `Scope: user`. The
   `recursive = false` fallback is therefore not needed.
2. **`defaultEnabled: false` holds, and `enabledPlugins` overrides it.** The plugin
   listed as `Status: ✘ disabled`; adding `{"enabledPlugins": {"df-probe@skills-dir": true}}`
   to settings flipped it to `Status: ✔ loaded` with no other change.
3. **`claude plugin validate` runs offline** against a plugin directory and exits 0
   (warning only, for a missing `author` field), so it is usable inside a Nix build
   sandbox. `claude plugin details <name>@skills-dir` additionally prints a component
   inventory and token cost, useful for eyeballing a built plugin.

Ongoing coverage, given there is no runtime to test:

- Eval-time assertions for within-plugin skill-name collisions (all variants) and
  cross-plugin flattened collisions (Codex and Cursor only).
- `claude plugin validate <path>` run over each built plugin derivation as a flake
  check, so manifest schema drift on a Claude Code upgrade fails CI rather than
  silently disabling a plugin.

## Risks

- **Skills-dir plugins are a younger surface than marketplace installs.** A Claude
  Code upgrade could change discovery rules. Escape hatch: the same `mkPlugin`
  derivations can be listed in a generated `.claude-plugin/marketplace.json` and
  registered via `extraKnownMarketplaces` with a `directory` source, without changing
  the plugin bundles themselves.
- **`enabledPlugins` entries persist per project indefinitely**, so renaming a plugin
  later strands them. Hence fixing the `df-` prefix now.
- **Namespacing changes invocation names** (`brainstorming` → `df-base:brainstorming`),
  which affects muscle memory and any cross-skill references written in skill bodies.
  Skill files that name other skills need an audit during migration.

## Follow-ups

- Generalise `task-implementer` into a tracker-agnostic core plus a beans-specific
  variant, then move it and `whats-next` into plugins.
- Evaluate Codex and Cursor plugin packaging once their local-install paths are
  verified; the renderer is already parameterised by variant.
- Add `mcpServers` (and, if wanted, `agents`/`commands`/`outputStyles`) to the plugin
  options when a plugin needs to ship one.
