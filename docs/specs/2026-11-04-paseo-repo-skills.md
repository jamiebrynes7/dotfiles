# Per-repository skills for Paseo Claude agents — spec

Date: 2026-11-04

Personal skills that apply only to particular repositories, declared in Nix and loaded
into Paseo's Claude agents when, and only when, the agent works in one of those
repositories.

## Problem

Some skills only make sense in one repository, or a handful. The motivating case is a
monorepo shared with thousands of engineers: personal skills can't be committed to its
`.claude/skills`, copying them into every checkout doesn't sync across machines, and
installing them globally in `~/.claude/skills` loads them in every other repository too.

Paseo has no way for a plugin to give agents skills, but a plugin hook can change how a
Claude agent is launched. That is enough to load a Claude Code plugin per agent.

## Goals

- Declare skills in Nix together with the repositories they apply to. A skill used by
  several repositories is declared once.
- A Claude agent created through Paseo in a matching repository loads exactly that
  repository's skills; agents anywhere else load none of them.
- Any checkout matches, including worktrees and checkouts on other machines, with no
  per-checkout setup.
- A broken setup never blocks agent creation, and it says so where the user will see it.
- The mechanism lives in this repository; downstream system repositories
  (`dotfiles-samsara`) declare their own skills against it.

## Non-goals

- **Codex.** It has no equivalent to `--plugin-dir`. Codex agents in a matching
  repository don't get the skills.
- **`claude` run from a terminal.** Only agents created through Paseo get the skills.
- **Upstream Paseo changes.** Notably, adding the Agent SDK's `plugins` option to
  Paseo's Claude provider options is out of scope; this design uses what Paseo accepts
  today.
- **The `dotfiles-zo7y` plugin epic** (`docs/specs/2026-08-02-agent-plugins.md`). This
  design is independent of it and doesn't need it to land first.
- **The skills themselves**, and `dotfiles-samsara`'s declarations.

## Upstream facts this design depends on

Checked against Paseo 0.15.0 and Claude Code 2.1.318 (the pinned versions).

- **`server.addHook("agent.create.before", …)`** receives `{ request: { config, env? } }`
  and may return a modified `config`, except `cwd`. (0.15.0 renamed the hooks; the old
  `server.before("agent.create")` / `server.on("agent.created")` registrations are
  deprecated, so this plugin uses only `addHook` names.) The returned config is **saved with the
  agent**: resume, reload and daemon restarts reuse it, and the hook never runs again
  for that agent. The hook payload has no agent id. A throw, an invalid result, or
  running past the **30-second hook timeout** (which also aborts the hook's signal)
  fails agent creation.
- **Hook output reaches the provider intact.** The hook result is validated against the
  protocol schema, where `providerOptions` is an open record. Only the Claude provider
  validates it against `ClaudeProviderOptionsSchema` (strict), then spreads it into the
  Agent SDK options.
- **`ClaudeProviderOptionsSchema` has `extraArgs: Record<string, string | null>`**,
  which the SDK passes to the Claude Code CLI as `--<key> <value>`. One value per flag.
  Paseo never sets `plugin-dir` itself; the only `extraArgs` key it treats specially is
  `settings`.
- **`claude --plugin-dir <path>`** loads a plugin folder for that session only, as
  `<name>@inline`. A path that is a symlink to the plugin folder loads (verified with a
  symlinked plugin folder: `Status: ✔ loaded`). Plugin skills are namespaced
  `<plugin>:<skill>`.
- **`server.addHook("agent.create.after", …)`** receives `{ agent }` (`id`, `cwd`,
  `provider`, …) when ordinary creation finishes. It is not fired for import or resume.
- **Plugin timeline rows.** A server handler can add a plugin-owned row to an agent's
  chat with `paseo.agents.ref(agentId).timeline.append({ type: "plugin", id, kind,
  version, data })`, drawn by a client renderer registered with
  `client.addTimelineRenderer`. Reusing `id` replaces the row. Toasts (`useToast`) are
  client-only; the daemon side cannot show one.

Still unverified, and the first thing the end-to-end check covers: that the Agent SDK
passes `extraArgs["plugin-dir"]` through to the CLI so the skills load in a real Paseo
agent.

## Architecture

```
dotfiles.programs.paseo.repoSkills  (Nix declarations: skill → repositories)
        │  invert at eval time
        ▼
one Claude Code plugin per repository (store)
        │  home-manager links
        ▼
~/.local/share/paseo-repo-skills/<owner>-<repo>   stable symlink per repository
~/.config/paseo-repo-skills/config.json           repository key → stable plugin path
        │  read on every agent creation
        ▼
repo-skills Paseo plugin
  server: agent.create.before sets providerOptions.extraArgs["plugin-dir"]
          agent.create.after appends any warning row
  client: renders the warning row
        │
        ▼
Claude agent launched with --plugin-dir → <owner>-<repo>:<skill> skills
```

## Nix surface

A new option on the existing Paseo module (`home/programs/paseo.nix`):

```nix
dotfiles.programs.paseo.repoSkills.<skill> = {
  source = ./skills/<skill>;              # directory containing SKILL.md
  repositories = [ "github.com/<owner>/<repo>" ];
};
```

- `<skill>` is the skill's name and its directory name inside the plugin.
- `source` is a directory containing `SKILL.md`, like the existing skill directories.
- `repositories` is a non-empty list of repository keys in normalised
  `host/owner/repo` form (see [Repository matching](#repository-matching)). Eval fails
  on a key that isn't in that form, so a pasted `git@…` or `https://…` URL is caught
  at eval instead of never matching.

When `repoSkills` is non-empty, the module enables the `repo-skills` Paseo plugin
(`dotfiles.programs.paseo.plugins.repo-skills`, package
`pkgs.dotfiles.paseo-plugin-repo-skills`) and installs the files below. When it is empty,
nothing is installed and the plugin is not added.

### Generated plugins

Nix inverts the declarations into one Claude Code plugin per repository key:

- **Name:** `<owner>-<repo>` from the key (`github.com/samsara-dev/backend` →
  `samsara-dev-backend`), so its skills appear as `samsara-dev-backend:<skill>`. Eval
  fails if two keys produce the same name.
- **Contents:** `.claude-plugin/plugin.json` (name, version, description, author) and
  `skills/<skill>/` for every skill that lists the repository. Each skill is copied and
  its `SKILL.md` frontmatter filtered for the `cc` variant with the existing
  `process-frontmatter` tool, as `mkSkillFiles` does for today's skills.
- Two skills with the same name can't both apply to one repository: attribute names
  are unique, so this holds by construction.

### Installed files

- Each plugin is linked to `~/.local/share/paseo-repo-skills/<owner>-<repo>`. The agent
  saves this path, not the store path, so rebuilds and garbage collection never leave
  a saved agent pointing at a deleted folder. A rebuild updates what the link points
  at, and every saved agent picks it up on its next launch.
- `~/.config/paseo-repo-skills/config.json` maps each repository key to its stable
  plugin path:

  ```json
  {
    "version": 1,
    "repositories": {
      "github.com/samsara-dev/backend": "/home/ubuntu/.local/share/paseo-repo-skills/samsara-dev-backend"
    }
  }
  ```

The Paseo plugin reads this file fresh on every agent creation rather than having the
mapping baked into its package. Changing which skills apply where then needs only a
`home-manager switch`, not a daemon restart. The plugin package itself doesn't change
when the mapping does.

## Repository matching

The hook lists every remote of the git repository at the agent's `cwd` and normalises
each URL to `host/owner/repo`:

- SSH (`git@github.com:owner/repo.git`, `ssh://git@github.com/owner/repo`) and HTTPS
  (`https://github.com/owner/repo`) forms give the same key.
- A trailing `.git`, a trailing `/`, a user (`git@`) and a port are dropped; the host is
  lowercased.

The agent matches a repository if **any** normalised remote equals one of the config's
keys. That covers forks whose `upstream` remote is the shared repository. Worktrees
share their repository's remotes, so they match too. If remotes match more than one
key, the first match in remote order wins and a warning row lists the others. Only one
plugin directory can be passed.

There is no path-based matching.

## The Paseo plugin

A repo-local plugin, `ts/paseo-plugin-repo-skills/`, packaged as
`packages/paseo-plugin-repo-skills/` over `buildPaseoPlugin`, like the existing plugins.

### Server half

**`agent.create.before` hook.** For agents whose provider isn't `claude`, it returns the
request unchanged. For Claude agents:

1. Read `~/.config/paseo-repo-skills/config.json` (the user's `$XDG_CONFIG_HOME` if
   set).
2. List the remotes of the repository at `config.cwd` and normalise them. If `cwd`
   isn't inside a git repository, or no remote matches a key, return the request
   unchanged.
3. If the matched plugin path doesn't exist, skip and warn.
4. If `providerOptions.extraArgs["plugin-dir"]` is already set, leave it untouched,
   skip and warn.
5. Otherwise return the config with `providerOptions.extraArgs["plugin-dir"]` set to
   the stable plugin path, keeping every other provider option and `extraArgs` key.

**Warnings.** The hook has no agent id, so it records each warning against the agent's
`cwd`. The `agent.create.after` hook takes the oldest pending warning for that agent's
`cwd`, appends it as a row to that agent's chat, and logs it. A pending warning whose
creation never finished (the create failed for another reason) is dropped after a
short timeout so it can't attach to a later agent.

### Client half

Registers a timeline renderer for the warning row: a compact card in theme colours
saying the repository's skills weren't loaded, and why (for example "config file is
not valid JSON: …", "plugin-dir already set to …", "plugin folder missing: …").

## Error handling

Agent creation never fails because of this plugin. The hook catches every error and
returns the request unchanged. Because Paseo fails creation when a hook runs past 30
seconds regardless of what it returns, the hook also bounds its own work: each `git`
call has a timeout of a few seconds, well inside the hook budget, and a timed-out call
is handled as "`git` fails or times out" below.

| Situation | Result |
|---|---|
| Not a Claude agent | No change, silent |
| `cwd` not in a git repository | No change, silent |
| No remote matches | No change, silent |
| Config file missing or invalid | No change, warning row + log |
| `git` fails or times out | No change, warning row + log |
| Matched plugin path missing | No change, warning row + log |
| `plugin-dir` already set | Left as is, warning row + log |
| Remotes match several keys | First match used, warning row + log |

A missing config file is a warning, not silent: the plugin is only installed when
`repoSkills` is non-empty, so the file should always exist alongside it.

## Testing seams

- **Flake check (Nix):** renders a fixture `repoSkills` declaration (two skills, one
  shared by two repositories) and checks the generated plugins (manifest name, skill
  directories, filtered frontmatter) and `config.json`. Eval-time assertions for bad
  repository keys and plugin name collisions are covered by the same check.
- **Unit tests (`node:test`):** remote URL normalisation and repository lookup in the
  plugin's server code, using Node's built-in test runner with no new dependencies, run
  as a flake check next to the plugin's typecheck.
- **Typecheck and SDK version checks:** the existing `<dir>-typecheck` and
  `<dir>-sdk-version` checks apply to the new plugin unchanged.
- **Manual end-to-end:** with a skill declared for this repository, create a Claude
  agent through Paseo in a worktree and confirm the skill loads as
  `<owner>-<repo>:<skill>`. Create one in another repository and confirm it doesn't.
  Break the config and confirm the warning row appears and the agent still starts.
