---
# dotfiles-9th1
title: Add the savePersistedConfig symlink guard
status: completed
type: task
priority: normal
created_at: 2026-09-21T17:26:11Z
updated_at: 2026-10-05T12:31:39Z
parent: dotfiles-a3i5
---

**Files:**
- Modify: `packages/paseo/default.nix:36` — add `configGuardMessage` to the `let` block, after `nodeArch`
- Modify: `packages/paseo/default.nix:38-66` — add `postPatch` inside `daemon.overrideAttrs`, above the existing `postInstall`

Background: `home/programs/paseo.nix` links `config.json` from the store. The daemon's `writePrivateFileAtomicSync` writes a temp file and `renameSync`s it over that path (`private-files.ts:35`); rename-over-destination is governed by the parent directory's write bit, and `$PASEO_HOME` must stay writable for `plugins/`, logs and the database. No permission stops it, so patch the daemon to refuse instead.

- [x] **Step 1: Add the sentinel to the `let` block**

After the `nodeArch` binding:

```nix
  # Sentinel shared by the postPatch guard below and the postInstall assertion.
  # Keep it quote-free: it is interpolated into a TypeScript string literal.
  configGuardMessage = "config.json is managed by Nix; edit dotfiles.programs.paseo.settings and run a home-manager switch";
```

- [x] **Step 2: Add the postPatch guard**

Inside `daemon.overrideAttrs (old: { ... })`, above the existing `postInstall`:

```nix
  # Nix owns $PASEO_HOME/config.json, and the daemon's atomic save would rename a temp
  # file over the store symlink. Refuse the write so a Settings/CLI edit fails loudly
  # instead of surviving until the next home-manager switch silently reverts it.
  # Scoped to savePersistedConfig: writePrivateFileAtomicSync is shared with the
  # managed-plugin sources.json and other daemon state that must stay writable.
  postPatch = (old.postPatch or "") + ''
    substituteInPlace packages/server/src/server/persisted-config.ts \
      --replace-fail 'import { existsSync, readFileSync } from "node:fs";' \
                     'import { existsSync, lstatSync, readFileSync } from "node:fs";' \
      --replace-fail 'writePrivateFileAtomicSync(configPath, JSON.stringify(result.data, null, 2)' \
                     'if (lstatSync(configPath).isSymbolicLink()) { throw new Error("${configGuardMessage}"); }
    writePrivateFileAtomicSync(configPath, JSON.stringify(result.data, null, 2)'
  '';
```

Both anchors are unique at the pinned v0.8.0: the `node:fs` import appears once, and the other `writePrivateFileAtomicSync` call site writes `DEFAULT_PERSISTED_CONFIG` (`persisted-config.ts:421`), not `result.data`.

- [x] **Step 3: Format**

Run: `nixfmt packages/paseo/default.nix`

- [x] **Step 4: Build**

Run: `nix build .#paseo -o /tmp/paseo-guard`

Expected: success. Slow — this is the npm build plus the eval-time source fetch. If it fails with `substituteInPlace: pattern not found`, upstream moved the anchor; re-read the pinned file and re-anchor:

```bash
curl -sL "https://raw.githubusercontent.com/getpaseo/paseo/$(jq -r .tag packages/paseo/hashes.json)/packages/server/src/server/persisted-config.ts" | grep -n "writePrivateFileAtomicSync\|from \"node:fs\""
```

- [x] **Step 5: Verify the guard reached the artifact**

Run: `grep -rl "config.json is managed by Nix" /tmp/paseo-guard/lib | head -3`

Expected: at least one path under `/tmp/paseo-guard/lib/paseo`. An empty result means the patched source never reached the bundle — do not commit.

- [x] **Step 6: Commit**

```bash
git add packages/paseo/default.nix
git commit -m "packages/paseo: refuse writes to a Nix-managed config.json" -m "Bean: dotfiles-9th1"
```

## Summary of Changes

Added a `postPatch` to `packages/paseo` that imports `lstatSync` and makes `savePersistedConfig` throw `configGuardMessage` when config.json is a symlink. Both `--replace-fail` anchors are unchanged and unique at v0.10.3. The guard sits inside the existing try, so the CLI sees it wrapped as `[Config] Failed to write …: config.json is managed by Nix…`. The build succeeds and the sentinel is in both compiled `persisted-config.js` files.
