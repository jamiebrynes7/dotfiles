---
# dotfiles-m8y6
title: Package the catppuccin-theme plugin
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:27:34Z
updated_at: 2026-09-21T17:30:07Z
parent: dotfiles-6zzi
---

**Files:**
- Create: `packages/paseo-plugin-catppuccin-theme/default.nix`

Every directory under `packages/` is auto-discovered by `flake.nix` and exposed as `pkgs.dotfiles.<dir>`, and `checks` includes all of `packages`, so this is built by `nix flake check` on both systems with no extra wiring. Directory name matches the plugin id so `plugins.catppuccin-theme.package = pkgs.dotfiles.paseo-plugin-catppuccin-theme` needs no lookup.

No `hashes.json` and no `update.sh`: the upstream repo publishes no tags or releases, the pin is a commit SHA bumped by hand, and omitting `update.sh` keeps `.github/workflows/auto-update.yml` from touching it. `packages/beans-daemon` is the precedent for a `default.nix`-only package.

- [ ] **Step 1: Write the package**

```nix
{ runCommand, fetchFromGitHub }:
let
  # No tags or releases upstream — paseo.cafe itself links a bare commit. Bumped by
  # hand, deliberately: plugin server code runs unsandboxed as the daemon user, so
  # every update is a reviewed commit rather than a nightly auto-update PR.
  src = fetchFromGitHub {
    owner = "sleeyax";
    repo = "paseo-plugins";
    rev = "905e46111e8abe887c91209b7d8fbabba3b81e29";
    hash = "sha256-MeEfwJhngWPQelHa6PpcK/Kn0YeYOgcmTOhaPiKbvQM=";
  };
in
# Copy the plugin subdirectory out rather than pointing config.json at
# "${src}/plugins/catppuccin-theme": the monorepo carries an unrelated app and a 1.4 MB
# screenshot, and this way only four files end up in the runtime closure.
runCommand "paseo-plugin-catppuccin-theme" { } ''
  cp -r ${src}/plugins/catppuccin-theme $out
  chmod -R u+w $out
  rm -rf $out/docs
''
```

The plugin needs no build step: its only import is `import type { ... } from "@getpaseo/plugin"`, which is host-supplied and erased at compile time, and its manifest declares no `build` array (which directory sources never run anyway).

- [ ] **Step 2: Format**

Run: `nixfmt packages/paseo-plugin-catppuccin-theme/default.nix`

- [ ] **Step 3: Build**

Run: `nix build .#paseo-plugin-catppuccin-theme -o /tmp/catppuccin`

Expected: success. A `cp: no such file` failure means upstream moved the plugin within the monorepo.

- [ ] **Step 4: Verify the output shape**

Run: `ls /tmp/catppuccin && cat /tmp/catppuccin/paseo-plugin.json`

Expected: `index.client.ts`, `package.json`, `paseo-plugin.json`, `tsconfig.json`, and no `docs` directory. The manifest reads `{ "id": "catppuccin-theme", "requirements": { "paseo": ">=0.8.0" } }` — confirm the id matches the directory name, and that the requirement admits the pinned paseo version in `packages/paseo/hashes.json`.

- [ ] **Step 5: Commit**

```bash
git add packages/paseo-plugin-catppuccin-theme/default.nix
git commit -m "packages: add the catppuccin-theme paseo plugin" -m "Bean: dotfiles-m8y6"
```
