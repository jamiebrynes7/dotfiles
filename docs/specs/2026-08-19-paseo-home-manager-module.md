# Paseo home-manager module — spec

Date: 2026-08-19

Pull [paseo](https://github.com/getpaseo/paseo) into this flake as a patched package
(`pkgs.dotfiles.paseo`) and a home-manager module (`dotfiles.programs.paseo`) that runs
the daemon as a user service — `systemd.user` on Linux, `launchd` agent on macOS.

Today this wiring lives downstream in `sys-warbird` as a flake input, a patch overlay,
and upstream's NixOS-only `services.paseo` module plus two `mkForce` escape hatches.
Upstream has no home-manager or darwin support, and its package does not build at any
release tag as-shipped.

## Goals

- Expose a patched paseo at `pkgs.dotfiles.paseo`, built against this repo's pinned
  nixpkgs, so a stale `npmDepsHash` fails in CI rather than at switch time on a host.
- Provide `home/programs/paseo.nix` following the repo's program-module pattern,
  covering both `systemd.user` and `launchd` from one module.
- Support `listenAddress`, `port`, a daemon password (both a plain option and a
  file-based one), and arbitrary extra environment variables.
- Make `~/.local/bin` reachable by the daemon and the agents it spawns *by default*, so
  the `claude` / `codex` wrappers work without a downstream `mkForce`.

## Non-goals

- No changes to `sys-warbird`. Cutting it over to this module is deliberately deferred
  to separate, later work. The module must be *capable* of everything that repo does
  today, but nothing there changes here.
- No relay support. `--no-relay` is passed unconditionally and no relay options are
  exposed.
- No `settings` / `config.json` rendering. Upstream warns declarative config.json
  clobbers CLI and mobile-app mutations on every restart; config.json stays purely
  runtime-managed.
- No system-level (NixOS / nix-darwin) module, and no new `nixosModules` /
  `darwinModules` flake outputs.
- No `user` / `group` / `openFirewall` / `inheritUserEnvironment` options — meaningless
  or unavailable in home-manager.
- No configuration of the `paseo` **CLI**'s connection target (`PASEO_HOST`) for
  interactive shells. See "Out of scope follow-ups".

## Upstream facts this design depends on

Verified against `getpaseo/paseo` at v0.3.1 and v0.4.0:

1. `nix/module.nix` is NixOS-only — `systemd.services`, `users.users`, `users.groups`,
   `networking.firewall`. No launchd, no `systemd.user`, no home-manager support.
2. `nix/package.nix` is **byte-identical** between v0.3.1 and v0.4.0, so both patches
   below are still required and neither is close to landing upstream.
3. `PASEO_PASSWORD` is read as **plaintext** and bcrypt-hashed at startup
   (`packages/server/src/server/config.ts:409`). There is no hashed-input env var.
4. Hostname allowlisting matches on the **`Host` header**, not the bind address
   (`packages/server/src/server/hostnames.ts`). Defaults allow `localhost`,
   `*.localhost`, and any literal IP. A disallowed host fails the websocket upgrade
   with `403 Host not allowed` (`websocket-server.ts:832`).
5. `nix/package.nix` exposes `npmDepsHash` as a **function argument** specifically so
   downstream flakes on a different nixpkgs can override it without `overrideAttrs`
   (`npmDepsHash` is destructured by `buildNpmPackage`, so `overrideAttrs` cannot reach
   it).
6. The server is not published to npm (`@getpaseo/cli` is; the `paseo` npm package is
   unrelated), so building from the flake input source is the only practical route.

Home-manager option types verified at the pinned rev (`4baa8ac`):

- `systemd.user.services.<n>.Service.Environment` is `coercedTo str toList (listOf str)`
  — an **attrset is not accepted**; env must be rendered to `"KEY=value"` strings.
- `launchd.agents.<n>.config.EnvironmentVariables` is `nullOr (attrsOf str)`.

## Package wiring

### `flake.nix` input

```nix
paseo = {
  url = "github:getpaseo/paseo/v0.3.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### `overlays/paseo.nix` (new directory)

A new top-level `overlays/` directory, holding overlay fragments that are not
`packages/`-style local derivations. `flake.nix` appends
`(import ./overlays/paseo.nix { inherit inputs; })` to `defaultOverlays`, **after**
`dotfilesOverlay` (which plain-assigns `dotfiles` and would otherwise clobber this).

The overlay extends rather than replaces the set, matching `crates/default.nix`:

```nix
{ inputs }:
final: prev:
let
  paseo = (final.callPackage "${inputs.paseo}/nix/package.nix" {
    npmDepsHash = "sha256-…";
  }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''…'';
  });
in
{
  dotfiles = (prev.dotfiles or { }) // { inherit paseo; };
}
```

Two patches are carried, each with the explanatory comment from
`sys-warbird/overlays/paseo.nix` adapted to the new mechanism:

1. **`npmDepsHash`.** The correct value is not knowable ahead of the build. Start from
   `lib.fakeHash`, build once, and take the `got:` hash from the failure — that is the
   expected workflow at every bump, not a one-off. `sys-warbird`'s current value
   (`sha256-oXz8hMk+5DlTYK8OndUAjB+RJMDbPqobVGXLFeoH++o=`) is worth trying first, but it
   was computed with paseo's own nixpkgs-unstable rather than this repo's `nixpkgs`
   26.05, so it may well not match. Every release tag ships a stale
   `nix/npm-deps.hash`: upstream's
   repair workflow runs on push to `main` and lands ~10 minutes *after* the release
   commit is tagged, so the tag always points at the pre-repair state (holds for v0.2.5,
   v0.3.0, v0.3.1). Passing it as a `callPackage` argument — rather than
   `sys-warbird`'s `npmDeps.overrideAttrs` — is the mechanism upstream provides for
   this. Expect to re-point it at every bump. Overriding is safe: `package-lock.json`'s
   integrity fields pin the fetched contents independently of this hash.
2. **`node-pty` prebuilds.** `scripts/trace-daemon.mjs` walks the JS module graph, so
   node-pty's prebuilt native binding never reaches `$out` and every terminal pane
   reports "Terminal worker not running". Same `cp` as upstream PR #3250.

Landing at `pkgs.dotfiles.paseo` means `mkPackages` (`removeAttrs pkgs.dotfiles
[ "internal" ]`) picks it up, so paseo enters `packages.*` **and** `checks.*` and
`nix flake check` builds it. That is a deliberate, several-minute-per-PR cost: it is the
only thing that catches a stale `npmDepsHash` after a nixpkgs or paseo bump. CI runs on
`ubuntu-latest`, so only the `x86_64-linux` build is exercised; the darwin build stays
evaluation-only until someone switches a Mac.

## Module: `home/programs/paseo.nix`

Standard repo pattern — `options.dotfiles.programs.paseo` + `config = lib.mkIf
cfg.enable { … }`. Not added to any profile in `home/profiles.nix`; opt-in per host.

### Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `enable` | `bool` | `false` | `mkEnableOption` |
| `package` | `package` | `pkgs.dotfiles.paseo` | `mkPackageOption`-style |
| `dataDir` | `str` | `"${config.home.homeDirectory}/.paseo"` | → `PASEO_HOME` |
| `listenAddress` | `str` | `"127.0.0.1"` | → `PASEO_LISTEN` with `port` |
| `port` | `port` | `6767` | |
| `hostnames` | `listOf str` | `[ ]` | → `PASEO_HOSTNAMES`, omitted when empty |
| `allowAnyHostname` | `bool` | `false` | → `PASEO_HOSTNAMES=true` |
| `password` | `nullOr str` | `null` | Store-visible; documented as such |
| `passwordFile` | `nullOr path` | `null` | Read at process start |
| `environment` | `attrsOf str` | `{ }` | Arbitrary extra env |
| `extraPath` | `listOf str` | `[ ]` | Prepended to the computed PATH |

Option descriptions must carry these specifics, because each is a real trap:

- `hostnames` — matched against the `Host` header, **not** the bind address. Additive to
  the built-in `localhost` / `*.localhost` / any-literal-IP defaults, never a
  replacement. Reaching the daemon at `http://warbird.lan:6767` requires
  `hostnames = [ "warbird.lan" ]`; `http://192.168.1.5:6767` needs nothing. A rejected
  host fails the websocket upgrade with `403 Host not allowed`, which typically presents
  as "the UI loads but never connects".
- `allowAnyHostname` — disables DNS-rebinding protection entirely; any web page you
  visit can then reach the daemon by name.
- `password` — the value is written into the Nix store, which is world-readable on the
  host. Prefer `passwordFile`.
- `passwordFile` — a path **outside** the store containing the plaintext password and
  nothing else. Read at each service start, so rotating the secret needs only a service
  restart, not a home-manager switch.

### Assertions

- `password` and `passwordFile` are mutually exclusive.
- `hostnames != [ ]` and `allowAnyHostname` are mutually exclusive.

### Launcher script

One `pkgs.writeShellScript "paseo-launcher"`, shared by both platforms, because launchd
has no `EnvironmentFile` equivalent and this is the only way `passwordFile` behaves
identically on macOS and Linux:

```sh
set -euo pipefail
export PATH="<computed>"
mkdir -p "$PASEO_HOME"
chmod 700 "$PASEO_HOME"
# only when passwordFile != null:
PASEO_PASSWORD="$(cat <passwordFile>)"
export PASEO_PASSWORD
exec <package>/bin/paseo-server --no-relay
```

- `set -euo pipefail` makes a missing or unreadable `passwordFile` a loud startup
  failure rather than a silently unauthenticated daemon.
- `mkdir -p` replaces upstream's `systemd.tmpfiles` rule, which home-manager has no
  equivalent for. `chmod 700` matches upstream's `0700`.
- `--no-relay` is unconditional.
- The `PASEO_PASSWORD` block is emitted only when `passwordFile != null`; `password`
  (the plain option) goes through the normal environment path instead.

PATH is computed as:

```
cfg.extraPath
  ++ [ "${config.home.homeDirectory}/.local/bin" ]
  ++ config.home.sessionPath
  ++ [ "${config.home.profileDirectory}/bin" ]
  ++ <platform system paths>
```

`~/.local/bin` is explicit and unconditional: `home/programs/claude-code/default.nix`
and `home/programs/codex/default.nix` both install their wrappers there via
`home.activation`, and no Nix profile directory covers it. This is precisely the
`mkForce` that `sys-warbird` currently carries.

Platform system paths:

- Linux: `/etc/profiles/per-user/<user>/bin`, `/run/current-system/sw/bin`,
  `/run/wrappers/bin`, `/nix/var/nix/profiles/default/bin`
- Darwin: `/etc/profiles/per-user/<user>/bin`, `/run/current-system/sw/bin`,
  `/nix/var/nix/profiles/default/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`

The list is de-duplicated (`lib.unique`) while preserving order.

### Environment

Non-secret variables go through each platform's native mechanism so they stay
introspectable via `systemctl --user show-environment` / `launchctl print`:

```
PASEO_HOME       = cfg.dataDir
PASEO_LISTEN     = "${cfg.listenAddress}:${toString cfg.port}"
PASEO_HOSTNAMES  = "true" | concatStringsSep "," cfg.hostnames   # omitted when neither applies
PASEO_PASSWORD   = cfg.password                                  # only when non-null
<cfg.environment>                                                # merged last, wins
```

`cfg.environment` is merged last so it can override any of the `PASEO_*` variables above
— that is what makes it a real escape hatch (it is how `sys-warbird` sets `BROWSER`).

**`PATH` is the one exception.** The launcher `export`s the computed PATH *after* the
unit environment has been applied, so a `PATH` entry in `cfg.environment` is silently
overwritten rather than honoured. `extraPath` is the supported knob, and the
`environment` option's description must say so explicitly — a silently-ignored PATH
override is exactly the kind of thing that costs an afternoon.

Rendering differs per platform, per the verified option types: Linux maps the attrset to
`[ "KEY=value" ]` with `lib.escapeShellArg` on each value (systemd's `Environment=`
performs shell-like unquoting, so values containing spaces must be quoted); darwin
passes the attrset straight to `EnvironmentVariables`.

### Services

- **launchd** (`lib.mkIf pkgs.stdenv.isDarwin`), mirroring `beans-daemon.nix`:
  `ProgramArguments = [ launcher ]`, `KeepAlive = true`, `RunAtLoad = true`,
  `EnvironmentVariables`, and `StandardOutPath` / `StandardErrorPath` at
  `${config.home.homeDirectory}/Library/Logs/paseo.log`.
- **systemd user** (`lib.mkIf pkgs.stdenv.isLinux`):
  `Unit.Description`, `Unit.After = [ "network.target" ]`,
  `Service.ExecStart = launcher`, `Service.Environment`,
  `Service.Restart = "on-failure"`, `Service.RestartSec = 5`,
  `Service.KillSignal = "SIGTERM"`, `Service.TimeoutStopSec = 15` (upstream's graceful
  shutdown window — the server handles SIGTERM with a 10s timeout),
  `Install.WantedBy = [ "default.target" ]`.

`home.packages = [ cfg.package ]` so the `paseo` CLI is available interactively, not
just the daemon.

The module's `enable` description notes that a systemd **user** service only survives
logout when `users.users.<name>.linger = true`, which home-manager cannot set — it is a
downstream system-config requirement.

## File layout

```
flake.nix                    # + paseo input, + overlay in defaultOverlays, + module check
overlays/                    # NEW directory
  paseo.nix                  # NEW — patched pkgs.dotfiles.paseo
home/programs/paseo.nix      # NEW — the module (auto-imported by home/default.nix)
CLAUDE.md                    # + overlays/ in Project Structure, + convention note
```

## Validation

1. `nix flake check` — now also builds `pkgs.dotfiles.paseo` on `x86_64-linux`, plus the
   existing `nixfmt` gate over the new files.
2. **Module eval check**, a new `checks.x86_64-linux.paseo-module`: evaluate a minimal
   `homeManagerConfiguration` (with `dotfiles.profiles.base = false` to keep it cheap)
   that enables the module with a non-default `listenAddress`, `port`, `passwordFile`,
   `hostnames`, and `environment`. Home-manager materialises user units through
   `xdg.configFile` (`modules/systemd.nix:458`), so the rendered unit is reachable at
   `hmConfig.config.xdg.configFile."systemd/user/paseo.service".source` — a plain store
   path a `runCommandLocal` can `grep` without building the activation package (and
   therefore without building paseo itself a second time). Assert:
   - `PASEO_LISTEN=` carrying the configured address and port
   - `PASEO_HOSTNAMES=` carrying the configured names
   - the `environment` escape-hatch variable
   - `--no-relay` in the launcher
   - `/.local/bin` in the launcher's PATH
   - the `passwordFile` read, and **absence** of any plaintext password in the store

   Linux-only: it asserts the systemd path, and CI has no darwin builder. The launchd
   path is covered by evaluation alone (`nix flake show` / `packages.aarch64-darwin`).
3. Manual, on a real host, deferred with the `sys-warbird` cutover: daemon starts, UI
   connects, a spawned agent can find `claude` on PATH, and a terminal pane works (the
   node-pty patch).

## Risk / rollback

- **`npmDepsHash` churn** is the known recurring failure. It is now a CI failure with
  the correct value in the build log's `got:` line, rather than a switch-time failure on
  a host. Bumping the input and the hash together is the expected maintenance.
- **CI time** grows by a full npm + node-gyp + sherpa build of paseo. Accepted: binary
  caching is planned for this repo, at which point the build happens once per bump
  rather than once per PR. No mitigation is designed in.
- **Nothing downstream changes**, so rollback is deleting the three new files and
  reverting `flake.nix` and `CLAUDE.md`. `sys-warbird` keeps working off its own input
  and overlay throughout.

## Out of scope follow-ups

Worth beans of their own, not built here:

- `sys-warbird` cutover: drop its `paseo` input, `overlays/paseo.nix`, the
  `services.paseo` block and both `mkForce` escape hatches; enable
  `dotfiles.programs.paseo` in `home.nix` with `environment.BROWSER` carrying the
  `wsl-open` value.
- CLI connection config: a `PASEO_HOST` session variable so the `paseo` CLI targets a
  non-default `port` without the user exporting it by hand.
- Relay support, if a self-hosted relay ever appears.
- An `update.sh`-style nightly bump for the paseo input + hash, matching the
  `packages/*/update.sh` convention.
