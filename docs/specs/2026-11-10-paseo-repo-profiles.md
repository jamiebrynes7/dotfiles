# Per-repository Claude profiles for Paseo agents — spec

Date: 2026-11-10
Supersedes: docs/specs/2026-11-04-paseo-repo-skills.md §Nix surface, §Generated plugins (keying only), §Architecture, §Installed files, §The Paseo plugin, §Error handling (the plugin's name, paths, config format and hook behaviour)

Generalise the `repo-skills` Paseo plugin into `repo-profiles`. It gives a Claude agent
a per-repository profile, matched by git remote: the existing repository skills, and
now a per-repository Claude Code settings file.

## Problem

Auto mode's classifier blocks `git push --force-with-lease=<branch>:<sha>` to a personal
`jbrynes/*` branch as `[Git Destructive]`, even when the task asked for that rewrite.
The default Git Destructive rule already allows lease-pinned pushes to a personal
branch. What the classifier doesn't know is that `jbrynes/*` branches in `samsara-dev`
repositories *are* personal. That fact can be given in `autoMode.environment` and
`autoMode.allow`. Claude Code reads `autoMode` only from user settings, managed settings,
or `--settings`, never from a project's `.claude/settings*.json`. User settings would
apply it to every repository, so it needs `--settings`, scoped to the repositories it
describes. The repo-skills plugin already scopes a CLI flag (`--plugin-dir`) this way.

## Goals

- Declare Claude Code settings per repository in Nix. A Claude agent created through
  Paseo in a matching repository launches with them; agents anywhere else don't.
- One plugin and one Nix option carry every per-repository Claude profile field.
  Skills and settings are declared the same way, keyed by repository, and match
  through the same repository lookup.
- Changing a repository's settings reaches its saved agents on their next launch,
  resumed ones included. No daemon restart is needed.
- Agent creation never fails because of this plugin, as before.

## Non-goals

- **The samsara-dev rule text, its declaration in `dotfiles-samsara`, and the rollout
  on devbox and devbox-1.** These belong to the mirador bean that motivated this spec.
- **Codex**, and **`claude` run from a terminal**, as before.
- **Migrating agents saved under the old `repo-skills` paths.** After the rename, their
  saved `plugin-dir` points at a link that no longer exists.
- **Settings for every repository.** Global settings stay in `~/.claude/settings.json`.

## Upstream facts this design depends on

These add to the repo-skills spec's list. They were checked against Paseo 0.15.4 (the
pinned version; 0.15.2's code is identical here) and Claude Code 2.1.318.

- **Paseo's Claude provider reads `extraArgs.settings` on every launch.** If Paseo sets
  no flag settings of its own, the value passes through to the CLI as
  `--settings <value>`. If it does set them (fast mode, ultracode, `disableAllHooks`
  for internal agents), it reads the value itself (`readClaudeCliSettings`): inline
  JSON if it starts with `{`, otherwise a path resolved against the agent's `cwd`. It
  then merges the result under its own settings, with its own winning. A missing or
  invalid file **throws**, which fails that launch.
- **`claude --settings <file>` feeds `autoMode` to the classifier.** Verified: an
  `autoMode.environment`/`autoMode.allow` entry in a `--settings` file shows up in
  `claude --settings <file> auto-mode config`, and is absent without the flag.
- `extraArgs` takes one value per flag. A repository therefore gets one settings
  file, rendered from all of its declarations.

## Architecture

```
dotfiles.programs.paseo.repoProfiles  (repository → { skills, settings })
        │  render at eval time, per repository key
        ▼
per repository: Claude Code plugin (if it has skills) + settings.json (if it has settings)
        │  home-manager links
        ▼
~/.local/share/paseo-repo-profiles/<owner>-<repo>/…   stable links
~/.config/paseo-repo-profiles/config.json             repository key → profile
        │  read on every agent creation
        ▼
repo-profiles Paseo plugin
  server: agent.create.before sets extraArgs["plugin-dir"] and/or extraArgs["settings"]
          warning rows as today
  client: renders the warning row
```

## Rename

`repo-skills` becomes `repo-profiles` everywhere: the Paseo plugin id,
`ts/paseo-plugin-repo-profiles/`, `packages/paseo-plugin-repo-profiles/`, the
`home/lib` renderer and its flake check, the config path
`$XDG_CONFIG_HOME/paseo-repo-profiles/config.json`, the link root
`$XDG_DATA_HOME/paseo-repo-profiles/`, log prefixes, and the timeline row's id and kind.
The old plugin, its config file and its links go away. Home-manager removes the files
when they stop being declared.

The Nix option `repoSkills` is replaced by `repoProfiles` (below). It's declared with
`lib.mkRemovedOptionModule`, whose message points at `repoProfiles`, so a downstream
declaration such as `dotfiles-samsara`'s fails eval with directions instead of being
silently ignored.

## Nix surface

One option on `home/programs/paseo.nix`, keyed by repository:

```nix
let
  deployChecklist = ./skills/deploy-checklist;   # declared once, shared by binding
in
{
  dotfiles.programs.paseo.repoProfiles."github.com/<owner>/<repo>" = {
    skills.deploy-checklist = deployChecklist;   # <skill name> = directory with SKILL.md
    settings = {
      autoMode.environment = [ "$defaults" "…" ];
      autoMode.allow = [ "$defaults" "…" ];
    };
  };
}
```

- **Key:** a repository key, validated as `repoSkills` keys were (normalised
  `host/owner/repo`, rejected at eval otherwise).
- **`skills`:** `attrsOf path`, from skill name to a directory containing `SKILL.md`.
  Names are held to the same rule as before (1-64 lowercase letters, digits or
  hyphens), and a missing `SKILL.md` is an eval error. A skill used by several
  repositories is one Nix value listed under each. Two modules that give one
  repository the same skill name with different sources conflict at eval.
- **`settings`:** the JSON format's type (`pkgs.formats.json { }`), so declarations from
  several modules merge through the module system: attrsets recursively, lists by
  concatenation, and conflicting scalars are an eval error. The value is otherwise
  freeform. Nix doesn't validate Claude Code's settings schema.
- Both fields default to empty. The plugin is enabled, and the files installed, when
  `repoProfiles` has at least one repository with non-empty skills or settings. The
  existing assertion that the Paseo module is enabled carries over to `repoProfiles`.

### Rendering

For each repository key, with plugin-name collisions (`<owner>-<repo>`, case-folded)
checked across all keys:

- non-empty `skills`: the Claude Code plugin, named `<owner>-<repo>`, with each skill
  copied and its frontmatter filtered for `cc`, as today;
- non-empty `settings`: a `settings.json` holding that value.

Each artefact gets a stable link under `$XDG_DATA_HOME/paseo-repo-profiles/` named
after `<owner>-<repo>`. The implementer picks the exact layout.

### Config file

`$XDG_CONFIG_HOME/paseo-repo-profiles/config.json`:

```json
{
  "version": 1,
  "repositories": {
    "github.com/samsara-dev/backend": {
      "pluginDir": "/home/ubuntu/.local/share/paseo-repo-profiles/samsara-dev-backend/plugin",
      "settings": "/home/ubuntu/.local/share/paseo-repo-profiles/samsara-dev-backend/settings.json"
    }
  }
}
```

`pluginDir` is present only if the repository has skills, and `settings` only if it has
settings. Each value is a stable link path, never a store path. A new file at a new
path, so its version starts at 1.

## The Paseo plugin

Repository matching (remote listing, normalisation, first match in remote order, a
warning when remotes match several keys) is unchanged.

### `agent.create.before`

For agents whose provider isn't exactly `claude`, the request is returned unchanged.
Otherwise, once the matched profile is found, each field is applied **independently**:

| Field | extraArgs key | Applied when |
|---|---|---|
| `pluginDir` | `plugin-dir` | the path is a directory |
| `settings` | `settings` | the path is a readable file |

For each field present in the profile:

1. If the target is missing, skip that field and warn.
2. If `extraArgs[key]` already equals our path, leave it (a re-created stored agent
   coming back through the hook). This is not a warning.
3. If `extraArgs[key]` is set to anything else, leave it, skip and warn. Paseo can't
   pass two `--settings` values, and the hook can't merge into someone else's file.
4. Otherwise set `extraArgs[key]` to the stable path. Every other provider option and
   `extraArgs` key is kept.

If one field is skipped, the other is still applied. A non-object
`providerOptions.extraArgs` skips both fields with one warning.

The hook only checks that the settings file is readable. It does not parse it: Nix
rendered it as JSON, and a parse failure would surface at launch anyway.

### Warnings

The existing ledger (token in env, claimed in `agent.open.before`, posted in
`agent.create.after`) is unchanged. The one change: a creation can now produce several
problems (a skipped field, a multi-match), and they are all reported in that agent's
single warning row. Each problem says which field it affects and why, and the row says
what was loaded, if anything. The client card renders the list.

## Error handling

| Situation | Result |
|---|---|
| Not a Claude agent | No change, silent |
| `cwd` not in a git repository | No change, silent |
| No remote matches | No change, silent |
| Config file missing or invalid | No change, warning row + log |
| `git` fails or times out | No change, warning row + log |
| `extraArgs` not an object | No change, warning row + log |
| A field's target missing | That field skipped, warning row + log |
| A field's extraArgs key already set elsewhere | That field left as is, warning row + log |
| Remotes match several keys | First match used, warning row + log |
| Any unexpected throw | No change, warning row + log |

**After creation.** A saved agent's `settings` path is read on every launch. If a later
rebuild drops that repository's `settings`, the link goes away, and the agent's next
launch fails (Paseo throws "Failed to read Claude settings file", or the CLI rejects
`--settings`). We accept this: it takes a deliberate un-declaration, and it fails
loudly. Recreating the agent fixes it. The same is true today for a dropped
`plugin-dir`.

## Testing seams

- **Flake check (Nix), renamed:** the fixture is rewritten as `repoProfiles`. It covers
  one skill shared by two repositories, a repository with settings only, one with
  skills and settings, and two modules contributing to one repository's settings, to
  show the merge. The check asserts the generated plugins (as before), the rendered
  `settings.json`, the config entries (fields present only when declared), and the
  eval errors for bad keys, bad skill names, a missing `SKILL.md` and name collisions.
- **Unit tests (`node:test`):** config parsing of the new shape. For field
  application, each field independently: set, already ours, set elsewhere, target
  missing, and one skipped while the other applies. Also that several problems
  produce one warning carrying all of them.
- **Typecheck and SDK version checks:** unchanged, under the new directory name.
- **Manual end-to-end** (the demo daemon from `ts/paseo-demo.sh`, or a switched host):
  with an `autoMode.environment` marker declared for this repository, create a Claude
  agent in a worktree. Confirm that the saved agent's `extraArgs.settings` is the stable
  link, and that `claude --settings <link> auto-mode config` shows the marker. Confirm
  skills still load. Pre-set `extraArgs.settings` and confirm the warning row appears
  and the skills still load. The real check, a lease-pinned push that isn't blocked,
  belongs to the mirador rollout.
