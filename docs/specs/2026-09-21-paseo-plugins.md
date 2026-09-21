# Bundling paseo plugins — spec

Date: 2026-09-21

Bundle paseo plugins through this repo: a `dotfiles.programs.paseo.plugins` option that
renders them into `$PASEO_HOME/config.json`, external plugins packaged under `packages/`,
and repo-local plugins written under a new top-level `ts/` tree.

The first external plugin is `catppuccin-theme` from `sleeyax/paseo-plugins`. There is no
repo-local plugin yet; `ts/` is designed here and built when one exists (see
"Implementation phasing").

Bundling plugins forces a second decision: plugins are expressible *only* through the
persisted config, so the module stops treating `config.json` as daemon-owned and takes
ownership of it unconditionally. A source patch to the vendored daemon keeps the daemon
from clobbering what Nix writes.

## Goals

- `dotfiles.programs.paseo.plugins.<id> = { package; enable; }`, lowering to config.json's
  `plugins` record, so a plugin is installed by a switch rather than by
  `paseo plugin install`.
- Nix owns `config.json` on every host where `dotfiles.programs.paseo.enable` is true,
  reproducing the daemon's own creation-time defaults so nothing is silently lost.
- The daemon refuses to overwrite a Nix-managed `config.json`, with an actionable error,
  rather than silently accepting an edit that the next switch reverts.
- External plugins are pinned by commit SHA and bumped by hand.
- Repo-local plugins get `tsc --noEmit` and an SDK-version check in `nix flake check`.
- A switch that changes the config restarts the daemon, so a plugin bump takes effect
  without a manual step.

## Non-goals

- No support for `github:` / `git:` / `npm:` plugin sources. They are install-time syntax
  the daemon resolves into a local directory; a store path is the only thing worth
  expressing declaratively (fact 1).
- No `manageConfig = false` escape hatch. It reinstates the conditional this spec deletes.
- No automated update of the external pin — no `hashes.json`, no `update.sh`.
- No typechecking, linting, or formatting of external plugin source.
- No TypeScript formatter or `.githooks/pre-commit` gate for `ts/` (follow-up).
- No changes to downstream system repos. `sys-warbird` needs the migration pass in
  "Risk and migration" before it cuts over, but nothing there changes here.

## Upstream facts this design depends on

Verified against `getpaseo/paseo` at v0.8.0, the pinned tag:

1. `PluginSourceSchema` is a discriminated union with exactly one variant, `directory`
   (`packages/protocol/src/messages.ts:199-207`). `paseo plugin install github:…` clones
   into `$PASEO_HOME/plugins/<id>/<commit>-<uuid>/checkout` and records a plain
   `directory` entry (`packages/server/src/server/plugins/index.ts:260`), so a store path
   is a first-class plugin source.
2. Plugins come only from the persisted config — `resolveConfigFromPersisted` reads
   `pluginsEnabled` / `plugins` straight off the file
   (`packages/server/src/server/config.ts:617-618`). There is no `PASEO_PLUGIN*`
   environment variable anywhere upstream, and plugins do not appear in the
   `resolveOverrideControlledPaths` family that reports env-driven config paths.
3. Directory plugins never need a writable directory: the compiler runs esbuild with
   `write: false` (`plugins/compiler.ts:411`).
4. `runPluginBuild` runs only on git install/update (`plugins/index.ts:245,551`);
   `installDirectory` never calls it. A manifest `build` array is dead for directory
   sources, so Nix must perform any dependency installation itself.
5. `@getpaseo/plugin*` specifiers are host-supplied and stay external to the plugin bundle
   (`plugins/plugin-sdk-specifiers.ts`). A plugin's `package.json` dependencies exist for
   typechecking only.
6. Plugins are read once, in `start()` (`plugins/index.ts:131-145`). `paseo reload`
   re-reads the file but does not re-activate source entries, and `reloadPlugin` uses the
   in-memory path (`plugins/index.ts:301`). A changed store path therefore requires a
   daemon restart.
7. Every field in `PersistedConfigSchema` is optional with no zod-level default
   (`persisted-config.ts:233-300`). `daemon.cors.allowedOrigins` and `app.baseUrl` exist
   only in `DEFAULT_PERSISTED_CONFIG`, which `loadPersistedConfig` writes solely when the
   file is absent (`persisted-config.ts:347,421`). A Nix-written config that omits them
   does not inherit them.
8. `writePrivateFileAtomicSync` writes a temp file and `renameSync`s it over the target
   (`private-files.ts:35`). Rename-over-destination is governed by the parent directory's
   write bit, so no permission on the symlink or its target can prevent it; `$PASEO_HOME`
   must stay writable for `plugins/`, logs and the database.
9. `savePersistedConfig` (`persisted-config.ts:466`) is reached only from
   `applySupportedPatch` (`daemon-config-store.ts:397,573`) and the `set-password` /
   `onboard` CLI commands. The startup path never calls it. `applySupportedPatch`
   persists *before* mutating in-memory state and restores the previous persisted config
   if the write throws, so a rejected write leaves no divergence.
10. `PASEO_PASSWORD` is read as plaintext and bcrypt-hashed at startup (`config.ts:474`),
    taking precedence over `daemon.auth.password`, so daemon auth survives a store-owned
    config.json via the module's existing `environmentCommand`.
11. `sleeyax/paseo-plugins` has no git tags and no releases. `plugins/catppuccin-theme` is
    four files (`paseo-plugin.json`, `index.client.ts`, `package.json`, `tsconfig.json`)
    plus a `docs/` directory holding a 1.4 MB screenshot. It imports `@getpaseo/plugin`
    only under `import type` and declares no `build`.

## Module: `home/programs/paseo.nix`

### `plugins` option

```nix
plugins = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      package = lib.mkOption { type = lib.types.path; };
      enable  = lib.mkOption { type = lib.types.bool; default = true; };
    };
  });
  default = { };
};
```

The attribute name is the plugin id. It is not read from the plugin's
`paseo-plugin.json`: that read would be import-from-derivation for a fetched source, and
`packages/paseo` stays the only IFD package here. A mismatch between the key and the
manifest id is not fatal: the daemon loads a configured plugin by its config key and
`plugins/runtime.ts` reads the manifest only for `assertPluginCompatibility`
(`runtime.ts:321,540`), never comparing ids. The configured id is what `paseo plugin ls`
and the contribution registry use.

`types.path` accepts a derivation or a `"${src}/plugins/foo"` string, so a downstream
system repo can point at an inline `fetchFromGitHub` without adding a `packages/` entry.

Each entry lowers to `{ source = "directory"; path = toString package; enabled = enable; }`.
`enable = false` keeps the plugin configured but stopped, matching config.json's own
`enabled` field, and is the declarative replacement for the Settings toggle.

### Rendering `config.json`

`home.file."<dataDirRelative>/config.json"` is written whenever `cfg.enable` is true. The
previous `settings != {}` gate is removed: any non-empty `settings` already made the
daemon's writes futile, so the conditional bought an ownership model the module could not
deliver.

The rendered value is:

```nix
lib.recursiveUpdate creationDefaults (pluginEntries // cfg.settings)
```

where `creationDefaults` reproduces fact 7 — `daemon.cors.allowedOrigins =
[ "https://app.paseo.sh" ]` and `app.baseUrl = "https://app.paseo.sh"` — and
`pluginEntries` is `{ pluginsEnabled = true; plugins = …; }` when `cfg.plugins != { }`,
otherwise `{ }`. `cfg.settings` is applied last, so `pluginsEnabled = false` and any
override of the defaults remain expressible.

`settings`'s description loses its "leave this empty and the daemon owns the file"
guidance and its `set-password` warning, and gains a pointer to `PASEO_PASSWORD` via
`environmentCommand` (fact 10).

### Assertions and warnings

- Assertion: every `plugins` attribute name matches `^[a-z][a-z0-9-]*$` (upstream's
  `PluginIdSchema`), failing at switch rather than at daemon start.
- The existing "settings requires dataDir inside the home directory" assertion becomes
  unconditional on `cfg.enable`, since the file is now always written with `home.file`.
- Warning when `cfg.enable && cfg.desktop.enable && !cfg.service.enable`: the desktop
  app's bundled daemon is not patched, so with no service daemon running it can overwrite
  the managed `config.json`. Not an assertion — starting the daemon by hand is legitimate.

### Activation

Two entries in `home.activation`, straddling the write boundary:

`entryBefore [ "writeBoundary" ]`:

- If `config.json` is a symlink, record `readlink` output for the comparison below.
- If `config.json` exists and is *not* a symlink, `mv` it to
  `config.json.daemon-<timestamp>` and `warnEcho` that a daemon-written config was moved
  aside. Required before the boundary or `home.file` refuses to link over it. This is the
  migration path and the recovery path for the unpatched desktop daemon; it never
  deletes.

`entryAfter [ "writeBoundary" ]`, ordered after the existing `paseoDataDirMode` entry:

- Re-read the link. If the target is unchanged, do nothing — an unrelated switch must not
  kill live agent sessions.
- If it changed, restart the daemon: on Darwin
  `launchctl kickstart -k gui/$(id -u)/org.nix-community.home.paseo`, guarded on
  `launchctl print` for that label succeeding; on Linux
  `systemctl --user try-restart paseo.service`, which no-ops when inactive.
- Skipped entirely when `service.enable` is false — there is no unit to restart.

Both use the `run` helper so `--dry-run` does not restart anything. The old link target is
carried between entries in a shell variable, which works because home-manager concatenates
DAG entries into a single bash script; if that coupling is unwanted, stash it in a
`$TMPDIR` file instead.

## Package: `packages/paseo` config-write guard

Added to the existing `daemon.overrideAttrs` in `packages/paseo/default.nix` as a
`postPatch`, not a `patches/` directory: a patch file would require `applyPatches` around
the `fetchFromGitHub`, which evaluation would have to build before it can `callPackage`
upstream's `nix/package.nix` — a second import-from-derivation. A `postPatch` runs inside
the existing derivation, leaving eval-time cost unchanged.

Two `substituteInPlace … --replace-fail` calls on
`packages/server/src/server/persisted-config.ts`:

1. Add `lstatSync` to the existing `node:fs` import.
2. Guard the write in `savePersistedConfig`, anchored on
   `writePrivateFileAtomicSync(configPath, JSON.stringify(result.data, null, 2)` — unique
   to that function, since the other call site writes `DEFAULT_PERSISTED_CONFIG`, and
   truncated before the `+ "\n"` so no newline escape enters the Nix string. The inserted
   guard throws when `lstatSync(configPath).isSymbolicLink()`, with a message naming
   `dotfiles.programs.paseo.settings` as the place to make the change.

`--replace-fail` makes an upstream rewrite fail the build rather than silently shipping an
unguarded daemon. Because that only proves the source changed, `postInstall` gains an
assertion — beside the existing node-pty one — grepping `$out` for the error message, so a
guard lost during bundling also fails the build.

The guard is deliberately scoped to `savePersistedConfig`, not
`writePrivateFileAtomicSync`, which is shared with managed-plugin `sources.json` and other
daemon state that must stay writable.

Consequences, both intended: `paseo daemon set-password` and `paseo onboard` now fail on
any host with a managed config, and Settings writes surface an error instead of an edit
that the next switch reverts.

## Package: `packages/paseo-plugin-catppuccin-theme`

A single `default.nix`, with the rev and hash literal in the file — no `hashes.json` and
no `update.sh`, so `.github/workflows/auto-update.yml` leaves it alone and every bump is a
reviewed commit. `packages/beans-daemon` is the precedent for a `default.nix`-only
package.

```nix
{ runCommand, fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "sleeyax";
    repo = "paseo-plugins";
    rev = "905e46111e8abe887c91209b7d8fbabba3b81e29";
    hash = "sha256-MeEfwJhngWPQelHa6PpcK/Kn0YeYOgcmTOhaPiKbvQM=";
  };
in
runCommand "paseo-plugin-catppuccin-theme" { } ''
  cp -r ${src}/plugins/catppuccin-theme $out
  chmod -R u+w $out
  rm -rf $out/docs
''
```

Copying the subdirectory out, rather than pointing `config.json` at
`"${src}/plugins/catppuccin-theme"`, keeps the 1.4 MB screenshot and the rest of the
monorepo build-time only; the runtime closure is four files.

Package directories are named after the plugin id, so
`plugins.catppuccin-theme.package = pkgs.dotfiles.paseo-plugin-catppuccin-theme` needs no
lookup table.

## Repo-local plugins: `ts/`

`ts/default.nix` is an overlay fragment in the same slot as `crates/default.nix`: imported
into `defaultOverlays`, kept out of `flake.nix` so the flake stays language-agnostic. It
exports:

- `buildPaseoPlugin { pname; src; }` — auto-filled by `callPackage` exactly as
  `buildLocalRustBin` is, so `packages/paseo-plugin-<name>/default.nix` is a one-liner
  over it, mirroring `packages/beans-daemon`.
- `dotfiles.internal.tsChecks` — merged into `checks` in `flake.nix` next to
  `rustChecks`, one line per system. `internal` is already stripped from the packages
  output by `mkPackages`.

Source lives at `ts/paseo-plugin-<name>/`: `paseo-plugin.json`, `index.client.tsx` and/or
`index.server.ts`, the `client/` `server/` `shared/` directories, `package.json`,
`package-lock.json`, `tsconfig.json`.

**The shipped derivation is a plain copy.** `buildPaseoPlugin` uses a `lib.fileset` source
excluding `node_modules` and build output, and runs no npm: the SDK is host-supplied and
type-only (facts 4 and 5). npm appears only in the checks, so a type error makes one check
red instead of making the plugin unbuildable.

Two checks per repo-local plugin, discovered from the `ts/` tree the way `rustChecks`
covers the workspace rather than a single package:

- `typecheck` — `buildNpmPackage` running `tsc --noEmit`, `npmDepsHash` from the committed
  lockfile.
- `sdk-version` — `jq` the declared `@getpaseo/plugin` devDependency out of the plugin's
  `package.json` and compare it against `version` in `packages/paseo/hashes.json`, failing
  with both values named. Both are in-repo files read at build time, so no IFD. This turns
  SDK skew into a red check instead of a runtime load failure.

External plugins get neither check; their `package.json` is upstream's to fix. The pinned
hash plus the copy failing on a layout change is the coverage.

The repo devShell's `extraPackages` gains `pkgs.nodejs` so `npm` works inside `ts/`.

## File layout

```
home/programs/paseo.nix                              # plugins option, unconditional config render,
                                                     #   assertions/warning, activation entries
packages/paseo/default.nix                           # postPatch guard + postInstall sentinel grep
packages/paseo-plugin-catppuccin-theme/default.nix   # fetch + copy, rev pinned literally
ts/default.nix                                       # buildPaseoPlugin, internal.tsChecks      (phase 2)
ts/paseo-plugin-<name>/                              # repo-local plugin source                 (phase 2)
packages/paseo-plugin-<name>/default.nix             # one-liner over buildPaseoPlugin          (phase 2)
flake.nix                                            # tsChecks in checks, nodejs in devShell   (phase 2)
```

## Implementation phasing

Phase 1, now: the module changes, the `packages/paseo` guard, and
`packages/paseo-plugin-catppuccin-theme`. This is a complete, shippable change — a plugin
installed by a switch and a config Nix owns.

Phase 2, when a repo-local plugin exists: `ts/`, `buildPaseoPlugin`, `tsChecks`, and the
`flake.nix` wiring. Building it earlier means an npm toolchain, a lockfile and two checks
with no inhabitant.

## Validation

- `nix flake check` builds the patched paseo and every plugin package on both
  `aarch64-darwin` and `x86_64-linux`, since `checks` already includes all of `packages`.
- The `postInstall` grep proves the config guard survived bundling.
- On one host, after `switch`:
  - `readlink ~/.paseo/config.json` points into the store, and the file contains
    `pluginsEnabled`, the `catppuccin-theme` entry, and the creation defaults.
  - `paseo plugin ls` shows `catppuccin-theme` as `running`.
  - Four Catppuccin flavours appear under Settings → Appearance.
  - `paseo daemon set-password x` fails with the guard's message.
  - A pre-existing daemon-written `config.json` was moved to `config.json.daemon-<ts>`.
  - A second switch with a bumped pin restarts the daemon and `paseo plugin ls` shows the
    new path; a switch that changes nothing does not restart it.

There is no automated test for module behaviour: `nix flake check` never evaluates anything
under `home/`, and this change does not add a harness. The verification commands in the
plan's tasks are ad-hoc `nix eval` invocations against `flake.lib.mkHomeManagerSystem`,
which reach the rendered config, the assertions, the warnings and the activation scripts
without building anything.

A `home-eval` check that would put those assertions under CI is already planned in bean
`dotfiles-d6t2`. Wiring the paseo module's assertions into it is a follow-up once that
lands, not a dependency of this work.

## Risk and migration

- **Patch anchors rot.** An upstream rewrite of `savePersistedConfig` or the `node:fs`
  import fails the build on the nightly paseo bump PR. Loud, never reaches a host, fixed
  by re-anchoring. Escape hatch: drop the `postPatch` and rely on the activation
  move-aside alone.
- **Declarative config discards daemon-persisted state.** On every host, inspect
  `~/.paseo/config.json` before the first switch and port anything beyond the creation
  defaults — password, providers, agent/terminal profiles, dictation — into `settings`.
  `sys-warbird` needs this pass. The activation step moves the old file aside rather than
  deleting it, so the data survives.
- **Restart interrupts running agent sessions.** Mitigated by restarting only when the
  config's store path actually changed.
- **Plugin code is unsandboxed**, running as the daemon user with its `PATH`. The
  catppuccin plugin is client-only theme data, pinned by commit SHA and bumped by hand,
  which is the trust posture this spec sets for external plugins generally.

## Out of scope follow-ups

- A TypeScript formatter and a `.githooks/pre-commit` gate for `ts/`.
- A check that an external plugin's `requirements.paseo` range still admits the pinned
  paseo version — the thing `assertPluginCompatibility` enforces at load time.
- Cutting `sys-warbird` over to the `plugins` option.
- Covering this module's assertions and warning with the `home-eval` flake check planned
  in bean `dotfiles-d6t2`.
