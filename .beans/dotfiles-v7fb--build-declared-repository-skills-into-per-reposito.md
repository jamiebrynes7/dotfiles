---
# dotfiles-v7fb
title: Build declared repository skills into per-repository Claude Code plugins
status: completed
type: task
priority: normal
created_at: 2026-11-04T15:36:09Z
updated_at: 2026-11-04T18:21:11Z
parent: dotfiles-l44k
---

**Spec:** `docs/specs/2026-11-04-paseo-repo-skills.md` — Nix surface (Generated plugins, Installed files), Testing seams (flake check)

## What to build

Declaring skills under `dotfiles.programs.paseo.repoSkills` and switching produces one Claude Code plugin per declared repository, installed behind a stable link, plus the config file that maps each repository key to that link. Someone can load a repository's skills by hand with `claude --plugin-dir <link>`. Nothing loads them automatically yet; that's the next ticket.

Option shape (decision):

```nix
dotfiles.programs.paseo.repoSkills.<skill> = {
  source = ./skills/<skill>;              # directory containing SKILL.md
  repositories = [ "github.com/<owner>/<repo>" ];  # non-empty, normalised host/owner/repo
};
```

## Acceptance criteria

- [x] With two skills declared, one shared by two repositories, a switch installs `~/.local/share/paseo-repo-skills/<owner>-<repo>` for each repository as a link into the store. Each contains a plugin manifest named `<owner>-<repo>` and exactly the skills that list that repository.
- [x] `claude --plugin-dir ~/.local/share/paseo-repo-skills/<owner>-<repo> plugin list` reports the plugin as loaded.
- [x] Each installed `SKILL.md` has its frontmatter filtered for the `cc` variant (a `cursor:`/`codex:`-prefixed key in the source is absent; a `cc:`-prefixed key appears unprefixed).
- [x] `~/.config/paseo-repo-skills/config.json` is `{ "version": 1, "repositories": { "<key>": "<stable link path>" } }` with one entry per repository.
- [x] Evaluation fails with an assertion naming the key when a repository key is not normalised `host/owner/repo` (e.g. a pasted `git@github.com:o/r.git` or `https://…` URL).
- [x] Evaluation fails with an assertion naming both keys when two repository keys produce the same plugin name.
- [x] With `repoSkills` empty, neither the links nor the config file are installed.
- [x] A flake check renders a fixture declaration and checks the generated plugins and config; it goes red if a skill is missing from a repository's plugin.

## Constraints

- The plugin's on-disk name and its manifest name are the same `<owner>-<repo>` string.
- No import-from-derivation is introduced.

## Summary of Changes

- `dotfiles.programs.paseo.repoSkills.<skill> = { source; repositories; }` (`home/programs/paseo.nix`). When paseo is enabled and it is non-empty, it links one Claude Code plugin per repository at `$XDG_DATA_HOME/paseo-repo-skills/<owner>-<repo>` and writes `$XDG_CONFIG_HOME/paseo-repo-skills/config.json`. It warns if `repoSkills` is set while paseo is disabled.
- `home/lib/paseo-repo-skills/default.nix`: a `render` library inverts skill → repositories into per-repository plugins (manifest name == link name; SKILL.md filtered for `cc`) and the config. It reports errors that the module turns into assertions: non-normalised keys, plugin-name collisions (compared case-insensitively, for macOS), skill names outside `[a-z0-9-]{1,64}`, and a `source` with no SKILL.md.
- `processSkill` is hoisted out of `mkSkillFiles` and exported. The 22 existing skill derivations are unchanged.
- New `paseo-repo-skills` flake check (`home/lib/paseo-repo-skills/check.nix`) renders a fixture, checks the plugins, frontmatter and config, and asserts each error case. It was confirmed to go red when a plugin is missing a skill.
- Verified by hand: home-manager evals (fixture, empty, bad key, paseo disabled), and `claude --plugin-dir <symlink> plugin list` → `acme-api@inline ✔ loaded`.
- The `repo-skills` Paseo plugin itself is left to dotfiles-ki8f. Follow-up: dotfiles-zr0x (module-wiring cases once the home-eval harness lands).
