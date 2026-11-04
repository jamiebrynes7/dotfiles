---
# dotfiles-v7fb
title: Build declared repository skills into per-repository Claude Code plugins
status: todo
type: task
created_at: 2026-11-04T15:36:09Z
updated_at: 2026-11-04T15:36:09Z
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

- [ ] With two skills declared, one shared by two repositories, a switch installs `~/.local/share/paseo-repo-skills/<owner>-<repo>` for each repository as a link into the store. Each contains a plugin manifest named `<owner>-<repo>` and exactly the skills that list that repository.
- [ ] `claude --plugin-dir ~/.local/share/paseo-repo-skills/<owner>-<repo> plugin list` reports the plugin as loaded.
- [ ] Each installed `SKILL.md` has its frontmatter filtered for the `cc` variant (a `cursor:`/`codex:`-prefixed key in the source is absent; a `cc:`-prefixed key appears unprefixed).
- [ ] `~/.config/paseo-repo-skills/config.json` is `{ "version": 1, "repositories": { "<key>": "<stable link path>" } }` with one entry per repository.
- [ ] Evaluation fails with an assertion naming the key when a repository key is not normalised `host/owner/repo` (e.g. a pasted `git@github.com:o/r.git` or `https://…` URL).
- [ ] Evaluation fails with an assertion naming both keys when two repository keys produce the same plugin name.
- [ ] With `repoSkills` empty, neither the links nor the config file are installed.
- [ ] A flake check renders a fixture declaration and checks the generated plugins and config; it goes red if a skill is missing from a repository's plugin.

## Constraints

- The plugin's on-disk name and its manifest name are the same `<owner>-<repo>` string.
- No import-from-derivation is introduced.
