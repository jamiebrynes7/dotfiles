# Beans Daemon — Options Review

A daemon that multiplexes `beans-serve` instances across many projects on a single dev box. Triggered by `cd`-into-a-project pings; presents a unified web launcher for switching between projects.

## Motivation

Today `beans-serve` runs per-project on port 8080, so working across multiple beans-tracked repos means manually starting servers and dealing with port collisions. We want: one always-running thing, fed by the shell, that owns process lifecycle and gives a single URL for browsing every project.

## Locked design choices (do not vary across approaches)

These were settled in the brainstorming dialogue and are not under review here:

- **Per-project beans-serve child processes**, each bound to a random loopback port. Project identity = nearest `.beans.yml` walking up; key = abs path of that dir.
- **cd-ping**: zsh `chpwd` hook fires a fire-and-forget message to the daemon. The daemon spawns beans-serve if needed, registers the project, bumps LRU rank.
- **LRU cap** of N projects warm at once (default 8). Spawning the (N+1)th evicts the project with the oldest LRU rank.
- **LRU rank** = `max(cd-ping time, browser heartbeat time)`.
- **Browser heartbeat**: launcher JS pings the daemon every 15s for whichever project is currently embedded in the iframe.
- **Launcher**: fixed port (default `:9000`) serves a project list + iframe panel pointing at the bare beans-serve port for the active project. No reverse proxy — iframe loads `localhost:<beans-port>` directly so beans-serve frontend's absolute asset paths stay valid.
- **Localhost-only, single-user, no auth.**
- **Language**: Rust.
- **OS targets**: macOS (nix-darwin) + NixOS, both wired through home-manager.
- **Registry**: ephemeral; rebuilt from cd-pings on each daemon start.
- **Agent traffic**: agents (Claude Code) use the `beans` CLI exclusively, never beans-serve. So the daemon doesn't need observability into agent activity.

The approaches below differ in **where the long-lived state lives** and **who supervises the per-project processes**.

## Approach 1: Standalone Rust daemon (recommended)

**Summary.** A single long-lived `beansd` Rust binary owns everything: in-memory project registry, child-process supervision (spawn/kill `beans-serve` via `tokio::process`), LRU bookkeeping, the launcher HTTP server (axum), and a Unix-socket control plane. The cd-hook fires `beansd cd $PWD` (or writes a one-line message directly to the socket). Autostarted via launchd (macOS) and systemd-user (NixOS), both wired through one `home/programs/beans-daemon.nix` module.

```
launchd / systemd-user
└── beansd                               (always running; owns :9000)
    ├── beans-serve (project A)          (loopback :41xxx)
    ├── beans-serve (project B)          (loopback :41xxx)
    └── beans-serve (project C)          (loopback :41xxx)
```

Likely crate stack: `tokio`, `axum` (for the HTTP launcher AND the UDS control plane), `tokio::process::Command`, `clap`, `serde`/`serde_json`, `tracing`, plus `rust-embed`/`include_dir` for embedding launcher static assets into the binary.

**Binary layout — recommendation: single binary `beansd` with subcommands.**

CLI surface: `beansd run` (daemon entrypoint launchd/systemd invokes), `beansd cd <dir>` (cd-hook target), `beansd ls`, `beansd stop <project>`, `beansd start <project>`.

The alternative is splitting into `beansd` (long-running daemon, embeds launcher static assets, ~10–15 MB) plus a thin `beansd-cli` client (UDS client only, ~3–5 MB stripped). The split mirrors `systemd` + `systemctl` and avoids loading the daemon's embedded asset bundle on every cd-hook invocation.

Going with a single binary because:

- The cd-hook is fire-and-forget (`(beansd cd $PWD &) >/dev/null 2>&1`), so cold-start latency never hits the visible shell prompt.
- One Rust crate, one binary in Nix, one home-manager module reference, one set of integration tests.
- We can split later if profiling shows the embedded assets actually matter on cold-start; the public CLI surface stays the same.

The split would be the right call if any of these change: cd-hooks become synchronous (they won't), the launcher assets balloon (unlikely — it's a small SPA), or we want to ship the client separately from the daemon (no plans to).

**Pros.**
- Single source of truth for state — registry, LRU, last-active all live in one process's memory. No file locking, no inter-process state sync.
- One mental model: one daemon, one set of APIs, one home-manager module, one log stream.
- Iterating on the launcher UI is a normal Rust rebuild.
- Crash recovery is free: launchd/systemd-user restarts the daemon; ephemeral registry repopulates as the user cd's around.
- "Spawn a child process and keep its handle" is identical on macOS and NixOS — the per-platform code is just service-unit generation, which home-manager already handles.
- Maps cleanly to a single `home/programs/beans-daemon.nix` module wrapping a `packages/beans-daemon/default.nix` Rust derivation.

**Cons.**
- We hand-roll a small process supervisor (~200 LOC including restart-on-crash for child beans-serve).
- One process = one blast radius; daemon crash kills all children. Mitigated by service-manager auto-restart + ephemeral registry rebuild.
- Heavier upfront Rust setup than equivalent Go (axum + tokio + clap + rust-embed) for what is fundamentally glue code.

## Approach 2: Stateless Rust CLI orchestrating per-project OS-managed services

**Summary.** No long-lived custom daemon for supervision. `beansd` is a thin Rust CLI: `beansd cd <dir>` translates into "ensure a `beans-project-<hash>` user service exists and is running." On macOS this means generating/loading a launchd plist via `launchctl bootstrap`; on NixOS, dynamically rendering systemd-user units (or pre-generating one per registered project via home-manager). A separate small `beansd-launcher` service serves `:9000`, the iframe page, and the heartbeat endpoint. Shared state (project list, ports, last-active times) lives in a JSON file under `~/.local/state/beansd/`.

```
launchd / systemd-user
├── beansd-launcher        (owns :9000, JSON state file)
├── beans-project-A        (loopback :41xxx)
├── beans-project-B        (loopback :41xxx)
└── beans-project-C        (loopback :41xxx)
```

**Pros.**
- Reuses the OS's mature process supervision (restart, log collection, kill on logout).
- Each project independently restartable / inspectable via `launchctl`/`systemctl`.
- No always-running custom-daemon supervisor process.

**Cons.**
- LRU eviction needs a side process or periodic timer to actually kill anything — there's no central long-running brain.
- Browser heartbeat goes to the launcher service, which then has to mutate the shared state file — file locking, race conditions, two-process coordination.
- Two flavors of OS service generation (launchd plist vs systemd unit) doubles the platform-specific code, where Approach 1's child-spawn code is identical on both OSes.
- Dynamic launchd plist generation is fiddly: escaping, `launchctl bootstrap` quirks, ownership of the Library/LaunchAgents file.
- Total LOC ends up similar to Approach 1 once you factor in the launcher service, eviction timer, plist generation, and locking around the state file. Less custom supervision, more platform glue and IPC.

## Approach 3: Compose existing tools — Caddy + thin Rust shim

**Summary.** Use Caddy for static-asset serving (the launcher's HTML/JS) and lean on a thin Rust shim for the parts Caddy can't do: child-process management, cd-pings, LRU, heartbeat. Caddy serves the launcher page on `:9000`; launcher JS calls into the shim's HTTP API (proxied through Caddy) for project list and embeds beans-serve via iframe.

```
launchd / systemd-user
├── caddy                  (static :9000 + reverse-proxies /api → shim)
└── beansd-shim            (child supervisor + cd-ping handler + LRU + heartbeat)
    ├── beans-serve A
    └── beans-serve B
```

**Pros.**
- Caddy handles HTTP serving robustly (MIME types, range requests, future HTTPS if ever wanted).
- Less hand-rolled HTTP code in the shim.

**Cons.**
- Two processes to coordinate where one would do; new failure modes (shim alive but Caddy down, shim restarted but Caddy still has cached state).
- Caddy is a heavy dependency (~30 MB binary) for serving five static files and reverse-proxying to a Unix socket.
- We still write the shim, which is the bulk of the code anyway.
- More user setup: two services in home-manager, one Caddyfile, one Rust binary.
- The launcher's iframe + heartbeat behavior is custom JS regardless; Caddy isn't doing meaningful work.

## Recommendation

**Approach 1.** It's the simplest mapping of the problem to code: one process, one source of state, one home-manager module. Approach 2 trades self-managed supervision for OS-managed supervision but pays back the savings in cross-platform unit generation and inter-process state sync. Approach 3 adds a heavy dependency (Caddy) and a coordination problem to save HTTP serving code that axum gives us for ~30 LOC.
