---
# dotfiles-g2b5
title: Rename repo-skills to repo-profiles and key skills by repository
status: completed
type: task
priority: normal
created_at: 2026-11-10T09:36:04Z
updated_at: 2026-11-10T09:50:59Z
parent: dotfiles-vg6h
---

**Spec:** `docs/specs/2026-11-10-paseo-repo-profiles.md`: §Rename, §Nix surface (`skills` field), §Rendering (plugins), §Config file (`pluginDir`), §The Paseo plugin (plugin-dir field)

## What to build

Repository skills are declared per repository as `dotfiles.programs.paseo.repoProfiles."host/owner/repo".skills.<name> = <dir with SKILL.md>` and load into Paseo Claude agents exactly as `repoSkills` does today. They go through the renamed `repo-profiles` Paseo plugin, its new config file (one `{ pluginDir }` entry per repository) and its new link root. Everything named `repo-skills` (plugin id, ts and package directories, renderer, flake check, config and data paths, log prefixes, timeline row id/kind) becomes `repo-profiles`. There's no new behaviour beyond the rename and the option reshape. `settings` is the next ticket.

## Acceptance criteria

- [x] A Claude agent created through Paseo in a repository declared under `repoProfiles` with skills loads them as `<owner>-<repo>:<skill>`, and an agent in an undeclared repository loads none
- [x] Declaring `dotfiles.programs.paseo.repoSkills` fails eval with a message that names `repoProfiles`
- [x] The renamed flake check renders a fixture where one skill value is shared by two repositories, and asserts both generated plugins and the config's `pluginDir` entries
- [x] Bad repository keys, bad skill names, a missing `SKILL.md` and plugin-name collisions each still fail eval with a message naming the offender
- [x] Two modules that give one repository the same skill name with different sources fail eval
- [x] No `repo-skills` / `repoSkills` name remains outside `docs/specs/` and `.beans/`, apart from the removed-option shim
- [x] The `<dir>-typecheck`, `<dir>-sdk-version` and unit-test checks run under the new directory name

## Constraints

- Agent creation never fails because of the plugin. Every warning path in the existing error table still produces a warning row and leaves the request unchanged.
- The plugin is installed only when some repository has a non-empty profile, and the disabled-paseo assertion still fires.

## Notes

Once this lands, re-word `dotfiles-zr0x` (home-eval coverage of the module wiring) to `repoProfiles`.

## Summary of Changes

Renamed the repo-skills Paseo plugin to repo-profiles throughout: plugin id, ts/ and packages/ dirs, the home/lib renderer and its flake check, config and data paths, log prefixes, timeline row id/kind and the warning token env var. Replaced `dotfiles.programs.paseo.repoSkills` (skill → repositories) with `repoProfiles."host/owner/repo".skills.<name> = <path>`. The option type lives in the renderer lib, so the check can evaluate module merging. `repoSkills` is now an mkRemovedOptionModule that points at repoProfiles. config.json maps each key to `{ pluginDir }`, and plugins link at `paseo-repo-profiles/<owner>-<repo>/plugin`. Profiles with nothing to load are left out of the config so they can't shadow a later-matched profile. Verified with the flake checks, home-manager evals and a demo-daemon run: an agent in a declared repo loaded the skills, and one outside it didn't.
