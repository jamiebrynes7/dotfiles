# Beans Daemon (`beansd`) — Spec

A long-lived per-user daemon that multiplexes `beans-serve` instances across many projects on one dev box, with a unified web launcher for switching between them.

## Goals

- Single user-facing entry point (`http://localhost:9000`) for browsing every beans project on the machine.
- Eliminate manual `beans-serve` startup and per-project port collisions.
- Activate a project automatically on `cd` into its tree.
- Bound memory: at most N (default 8) `beans-serve` processes warm at once; evict the least-recently-used when the cap is hit.
- Distributed via the existing dotfiles flake; cross-platform across macOS (nix-darwin) and NixOS, autostarted via the appropriate user service manager.

## Non-goals

- Multi-user / multi-machine. Single-user, single-host only.
- Authentication. Localhost-only listeners; trust comes from filesystem perms on the Unix control socket.
- HTTPS, custom domains, or external exposure.
- Reverse-proxying beans-serve (the launcher iframes the bare per-project port). A future v2 may add a path- or subdomain-based proxy; the v1 design must not preclude it.
- Discovering projects without a cd-ping. The registry is built up as the user visits directories.
- Modifying upstream `beans` or `beans-serve`. Daemon treats them as opaque child processes.
- Persisting registry state across daemon restarts. Ephemeral by design.

## Architecture

```
launchd (macOS) / systemd-user (NixOS)
└── beansd run                                  (always running)
    ├── HTTP launcher  → 127.0.0.1:9000         (axum)
    ├── UDS control    → $XDG_RUNTIME_DIR/beans-daemon.sock
    │                                           (Linux) / ~/Library/Caches/
    │                                           beans-daemon/sock (macOS)
    │                                           (axum on UDS)
    ├── Project registry (in-memory)
    ├── LRU tracker (in-memory)
    └── Child supervisor
        ├── beans-serve (project A) → 127.0.0.1:41xxx
        ├── beans-serve (project B) → 127.0.0.1:41xxx
        └── beans-serve (project C) → 127.0.0.1:41xxx
```

Single Rust binary, single crate. Subcommands:

- `beansd run` — daemon entrypoint; service-manager-invoked.
- `beansd cd <dir>` — cd-hook target; sends a registration message to the UDS and exits.
- `beansd ls` — print the current registry as a table; UDS query.
- `beansd start <project-key>` — explicitly spawn a project's beans-serve.
- `beansd stop <project-key>` — stop a project's beans-serve.
- `beansd status` — print daemon health (running, uptime, registry size).

`<project-key>` is the absolute path to the directory containing the project's `.beans.yml`. `cd <dir>` walks upward from `<dir>` to find that file.

## Components

### 1. Cd-hook (zsh)

Installed by the home-manager module into `programs.zsh.initContent` when `dotfiles.programs.beans-daemon.enableZshIntegration` is true and `programs.zsh.enable` is true.

```zsh
beans_daemon_chpwd() {
  (beansd cd "$PWD" &) >/dev/null 2>&1
}
chpwd_functions+=(beans_daemon_chpwd)
```

Fire-and-forget: backgrounded, output discarded, never blocks the prompt. `beansd cd` itself opens the UDS, writes a single newline-delimited JSON message, closes the write half, and exits without waiting for the response. (The daemon still writes a response to its half of the socket; the client just doesn't read it. Other ops like `ls` and `status` do read the response.)

If the daemon socket is missing or unreachable (daemon down), `beansd cd` exits silently with code 0. The cd-hook never surfaces errors to the user.

### 2. Daemon UDS control plane

Newline-delimited JSON request/response over a Unix socket. Single-user; permissions `0600` on the socket file enforce isolation.

Request envelope:
```json
{ "op": "cd",      "args": { "cwd": "/abs/path" } }
{ "op": "ls",      "args": {} }
{ "op": "start",   "args": { "key": "/abs/path/to/proj" } }
{ "op": "stop",    "args": { "key": "/abs/path/to/proj" } }
{ "op": "status",  "args": {} }
{ "op": "heartbeat","args": { "key": "/abs/path/to/proj" } }
```

Response envelope:
```json
{ "ok": true,  "data": { ... } }
{ "ok": false, "error": "human-readable reason" }
```

`heartbeat` is also exposed over the HTTP launcher for browser JS (see §4); the UDS endpoint exists so other shell or editor integrations can refresh LRU rank without going through HTTP.

### 3. Project registry & LRU

In-memory; the only authoritative state in the daemon.

```rust
struct Project {
    key: PathBuf,           // abs path to dir containing .beans.yml
    display_name: String,   // dirname; can be overridden by `name:` in .beans.yml later
    last_used: Instant,     // max(cd-ping, heartbeat, explicit start)
    state: ProjectState,
}

enum ProjectState {
    Spawning { since: Instant },
    Healthy  { port: u16, pid: u32, spawned_at: Instant },
    Evicting { since: Instant },                            // kill in flight, no longer counts toward cap
    Dead     { reason: String, since: Instant },
}
```

Fields that only exist for live children (`port`, `pid`, `spawned_at`) live inside `Healthy` so they're statically unreachable in other states — no `Option<u16>` runtime checks, no "what if pid is set but state is Dead" inconsistencies.

LRU eviction is concurrent with spawning to keep cd-pings fast: the kill of an evicted project never blocks the spawn of a new one.

Sequence when a `cd` op needs to register a new project and `count(state ∈ {Spawning, Healthy}) >= cap`:

1. Find the project with the oldest `last_used` among Spawning/Healthy entries.
2. Transition that project to `Evicting`. It immediately stops counting toward the cap.
3. On a background tokio task: SIGTERM the child, wait up to 5 s for exit; if still alive, SIGKILL and wait up to 5 s more for `tokio::process::Child::wait` to reap it. On successful reap: drop the entry, log INFO. On reap timeout (rare — typically kernel D-state or signal queueing): drop the entry anyway, log WARN with the leaked pid and project key. The daemon does not retry; the leaked process is the OS's problem from that point and is bounded to one orphaned beans-serve worth of RAM until the next reboot.
4. Synchronously continue to spawn the new project.

The registry briefly holds (cap + 1) entries — one Evicting plus `cap` Spawning/Healthy. The cap is therefore a soft cap on live children; it's a hard cap on entries that count toward eviction decisions. This avoids cascading evictions when the user cd's rapidly between many projects.

Already-warm projects: a `cd` op for an existing key just bumps `last_used`; no spawn, no eviction.

### 4. HTTP launcher

Axum router on `127.0.0.1:9000` (configurable). All endpoints localhost-only.

Server-rendered HTML using `askama` (or `minijinja`) templates, with [HTMX](https://htmx.org/) for interactivity. No JS framework, no bundler, no `pnpm`, no `vite`. The only static assets shipped are:

- `htmx.min.js` (~14 KB) embedded via `include_bytes!`.
- A small hand-written `app.css`.

Routes (HTML responses unless noted):

- `GET /` — launcher shell: project list (left panel) + iframe panel (right). Server-renders the current project state on first load.
- `GET /partials/projects` — HTML fragment listing projects (used by HTMX polling: `hx-trigger="every 5s"` on the list panel swaps this in).
- `POST /api/heartbeat` body `key=<abs-path>` (form-encoded) — bumps `last_used`. The iframe panel includes a hidden HTMX-driven form: `<form hx-post="/api/heartbeat" hx-trigger="every 15s" hx-vals='{"key":"..."}'>`.
- `POST /api/projects/stop` body `key=<abs-path>` — stop a project; returns updated row HTML for HTMX swap.
- `POST /api/projects/start` body `key=<abs-path>` — re-spawn; returns updated row HTML for HTMX swap.

Project keys are absolute filesystem paths and are passed in form bodies rather than URL path segments to avoid path-segment encoding/decoding ambiguity in the router.

Bookmark URL convention: `http://localhost:9000/?project=<url-encoded-abs-path>`. Loading this auto-selects that project in the iframe panel via server-side rendering. Bookmarks survive daemon restarts; if the project isn't in the current registry, the page shows a "Not registered — cd into the directory to activate" empty state.

The iframe `src` is `http://localhost:<project-port>/`. The launcher does NOT proxy beans-serve; bare-port direct URLs work too (just without the launcher chrome and heartbeat).

HTMX is the right fit for v1's UI shape (list view + actions + periodic refresh + iframe). If launcher complexity outgrows it (e.g., real-time activity graphs, rich settings UI), the upgrade path is to swap in a small SPA — the HTTP API surface stays useful as JSON endpoints (the templates would render JSON instead of HTML fragments).

### 5. Child supervisor

For each `Project::Spawning`:

1. Pick a port: `TcpListener::bind("127.0.0.1:0")`, capture `local_addr().port()`, drop the listener.
2. Spawn `beans-serve serve --port <port> --beans-path <key>` via `tokio::process::Command`. Inherit the daemon's stdio so child output lands in the service-manager-collected log alongside the daemon's own. (Per-project log capture for an in-launcher log viewer is deferred to v1.1.)
3. Health-check: poll `GET http://127.0.0.1:<port>/` until it returns 200 or 5 s elapses. On success, mark `Healthy`. On timeout or non-2xx, log error, mark `Dead { reason: "startup timeout" }`, leave child running for one diagnostic round, then kill.
4. On unexpected exit (from `child.wait()`): mark `Dead`, log exit status. Restart up to 3 times within 60 s with exponential backoff (1 s, 4 s, 16 s); after that, leave dead and surface in the launcher.

The race between port-pick and child bind is accepted as v1 risk: another local process could grab the port in the millisecond gap. Mitigation: on detected child startup failure, retry the whole spawn once with a fresh port before giving up.

### 6. Configuration

`~/.config/beans-daemon/config.toml`. User-facing keys are optional (defaults baked into the daemon); `beans_serve_path` is required and rendered by the home-manager module from the Nix store.

```toml
launcher_port    = 9000
lru_cap          = 8
heartbeat_secs   = 15
log_level        = "info"            # tracing filter
beans_serve_path = "/nix/store/.../bin/beans-serve"
```

The home-manager module renders this file from Nix options and pins `beans_serve_path` to the absolute store path of the `beans-serve` binary it depends on (see Nix packaging). Manual edits to the rendered file are out of scope.

The daemon refuses to start if `beans_serve_path` doesn't point to an executable file — surfacing the error early in the service-manager log rather than at first cd.

## Nix packaging

### `packages/beans-daemon/default.nix`

`rustPlatform.buildRustPackage` derivation with a pinned `Cargo.lock`. No frontend build step — the launcher's HTML templates are compiled into the binary by `askama`, and `htmx.min.js` plus `app.css` are pulled in via `include_bytes!`/`include_str!` from the source tree. This means no `pnpm`, no `vite`, no separate frontend `mkDerivation`.

### `home/programs/beans-daemon.nix`

```nix
{ config, lib, pkgs, ... }:
let
  beans = pkgs.callPackage ../../packages/beans { };
  beans-daemon = pkgs.callPackage ../../packages/beans-daemon { };
  cfg = config.dotfiles.programs.beans-daemon;
in {
  options.dotfiles.programs.beans-daemon = {
    enable                = lib.mkEnableOption "Enable the beans daemon";
    launcherPort          = lib.mkOption { type = lib.types.port; default = 9000; };
    lruCap                = lib.mkOption { type = lib.types.ints.positive; default = 8; };
    heartbeatSecs         = lib.mkOption { type = lib.types.ints.positive; default = 15; };
    enableZshIntegration  = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the zsh chpwd hook that pings the daemon on each cd. Set to false to opt out.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ beans-daemon ];

    xdg.configFile."beans-daemon/config.toml".text = ''
      launcher_port = ${toString cfg.launcherPort}
      lru_cap = ${toString cfg.lruCap}
      heartbeat_secs = ${toString cfg.heartbeatSecs}
      beans_serve_path = "${beans}/bin/beans-serve"
    '';

    # launchd on Darwin
    launchd.agents.beans-daemon = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${beans-daemon}/bin/beansd" "run" ];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/beans-daemon.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/beans-daemon.log";
      };
    };

    # systemd-user on Linux
    systemd.user.services.beans-daemon = lib.mkIf pkgs.stdenv.isLinux {
      Unit.Description = "Beans daemon";
      Service = {
        ExecStart = "${beans-daemon}/bin/beansd run";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };

    programs.zsh.initContent = lib.mkIf
      (cfg.enableZshIntegration && config.programs.zsh.enable)
      (lib.mkAfter ''
        beans_daemon_chpwd() {
          (${beans-daemon}/bin/beansd cd "$PWD" &) >/dev/null 2>&1
        }
        chpwd_functions+=(beans_daemon_chpwd)
      '');
  };
}
```

Note: `enableZshIntegration` defaults to true since the cd-hook is the daemon's primary trigger and disabling it would defeat the point of running the daemon. It's exposed as an option so users on `bash`/`fish` (where the hook doesn't apply) can opt out cleanly without disabling the whole module.

### Coexistence with `home/programs/beans.nix`

The existing `home/programs/beans.nix` module is unchanged.

The daemon module pins its own reference to `packages/beans` via `callPackage`, so it works regardless of whether `dotfiles.programs.beans.enable` is true. This decouples the two modules: a user can enable `beans-daemon` without `beans`, or vice versa, and there is no runtime dependency on the `beans-serve` binary being on the user's `PATH` — the daemon's `config.toml` carries the absolute Nix store path.

When both modules are enabled (the common case), they pull from the same `packages/beans/default.nix` derivation, so there is no version skew between the user's CLI `beans`/`beans-serve` and the daemon's child `beans-serve`.

## Failure modes

| Failure | Behavior |
|---|---|
| Daemon down, user `cd`s | `beansd cd` silently no-ops. cd-hook never errors. User notices when launcher URL fails to load — service-manager auto-restart should make this rare. |
| Child beans-serve crashes | Supervisor restarts up to 3× / 60 s with exponential backoff, then marks Dead. Launcher shows red badge + "Restart" button. |
| Port pick race | Spawn retries once with a fresh port. Second failure marks Dead with descriptive error. |
| `.beans.yml` missing during cd | `beansd cd` walks up, finds nothing, exits 0. No registration. |
| LRU eviction kills active project | UI iframe goes 502; SPA's polling sees state=Dead and offers Restart. Cap default of 8 is high enough that this should be rare for one user. |
| UDS file orphaned from prior crash | On daemon start, unlink stale socket file before bind. |
| Two `beansd run` instances | Second binds to UDS and fails immediately; logs "socket in use" and exits non-zero. Service manager will not double-start. |
| Eviction kill times out (D-state child) | Entry dropped, WARN logged with leaked pid and key. One orphan beans-serve persists until reboot; bounded RAM cost, no retry. |
| Daemon crashes hard (SIGKILL or panic) | Service manager restarts the daemon; ephemeral registry rebuilds from cd-pings. Children of the previous incarnation are orphaned and continue running until the user kills them or reboots. The new daemon does not adopt them. Bounded RAM cost; documented limitation. |

## Testing

- **Unit**: registry operations (insert/evict/bump LRU), config parsing, key resolution from a path.
- **Integration**: spin up `beansd run` in a tempdir with a fake `beans-serve` (a tiny echo binary built in-tree), exercise UDS ops, assert process tree state. No tests against the real beans binary; that's covered upstream.
- **Manual smoke**: `nix run .#beans-daemon -- run` in one shell, `beansd cd $(pwd)` in another, `curl localhost:9000/api/projects`, observe child appears.

## Out of scope (future v1.x / v2)

- Reverse-proxy mode (path-prefix or subdomain) replacing the iframe.
- Per-project log capture (ring buffer) and in-launcher log viewer.
- SSE/WebSocket push for registry updates instead of polling.
- "Add by path" UI to register a project without cd'ing.
- `bash`/`fish` cd-hook integrations.
- Activity sparklines / metrics.

## Open questions

None — all design choices settled in brainstorming and options review. Implementation can proceed.
