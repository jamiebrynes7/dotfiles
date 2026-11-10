---
# dotfiles-g2b5
title: Rename repo-skills to repo-profiles and key skills by repository
status: todo
type: task
created_at: 2026-11-10T09:36:04Z
updated_at: 2026-11-10T09:36:04Z
parent: dotfiles-vg6h
---

**Spec:** `docs/specs/2026-11-10-paseo-repo-profiles.md`: §Rename, §Nix surface (`skills` field), §Rendering (plugins), §Config file (`pluginDir`), §The Paseo plugin (plugin-dir field)

## What to build

Repository skills are declared per repository as `dotfiles.programs.paseo.repoProfiles."host/owner/repo".skills.<name> = <dir with SKILL.md>` and load into Paseo Claude agents exactly as `repoSkills` does today. They go through the renamed `repo-profiles` Paseo plugin, its new config file (one `{ pluginDir }` entry per repository) and its new link root. Everything named `repo-skills` (plugin id, ts and package directories, renderer, flake check, config and data paths, log prefixes, timeline row id/kind) becomes `repo-profiles`. There's no new behaviour beyond the rename and the option reshape. `settings` is the next ticket.

## Acceptance criteria

- [ ] A Claude agent created through Paseo in a repository declared under `repoProfiles` with skills loads them as `<owner>-<repo>:<skill>`, and an agent in an undeclared repository loads none
- [ ] Declaring `dotfiles.programs.paseo.repoSkills` fails eval with a message that names `repoProfiles`
- [ ] The renamed flake check renders a fixture where one skill value is shared by two repositories, and asserts both generated plugins and the config's `pluginDir` entries
- [ ] Bad repository keys, bad skill names, a missing `SKILL.md` and plugin-name collisions each still fail eval with a message naming the offender
- [ ] Two modules that give one repository the same skill name with different sources fail eval
- [ ] No `repo-skills` / `repoSkills` name remains outside `docs/specs/` and `.beans/`, apart from the removed-option shim
- [ ] The `<dir>-typecheck`, `<dir>-sdk-version` and unit-test checks run under the new directory name

## Constraints

- Agent creation never fails because of the plugin. Every warning path in the existing error table still produces a warning row and leaves the request unchanged.
- The plugin is installed only when some repository has a non-empty profile, and the disabled-paseo assertion still fires.

## Notes

Once this lands, re-word `dotfiles-zr0x` (home-eval coverage of the module wiring) to `repoProfiles`.
