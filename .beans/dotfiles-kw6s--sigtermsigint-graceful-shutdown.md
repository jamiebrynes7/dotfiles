---
# dotfiles-kw6s
title: SIGTERM/SIGINT graceful shutdown
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:41:45Z
updated_at: 2026-05-10T14:19:13Z
parent: dotfiles-5h2f
---

**Files:**
- Modify: `packages/beans-daemon/src/run.rs`

- [x] **Step 1: Update the select to honour signals**

In `packages/beans-daemon/src/run.rs`, replace the final `tokio::select!` with:
```rust
    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut sigint  = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
    tokio::select! {
        _ = sigterm.recv() => { tracing::info!("SIGTERM received; shutting down"); }
        _ = sigint.recv()  => { tracing::info!("SIGINT received; shutting down"); }
        r = uds_task       => { tracing::error!(?r, "UDS server exited unexpectedly"); }
        r = http_task      => { tracing::error!(?r, "HTTP server exited unexpectedly"); }
    }

    // Best-effort: SIGTERM all healthy children. Service manager will reap us;
    // each child's own shutdown handler should clean up.
    let reg = registry.lock().await;
    for p in reg.iter() {
        if let crate::registry::ProjectState::Healthy { pid, .. } = &p.state {
            let _ = nix::sys::signal::kill(
                nix::unistd::Pid::from_raw(*pid as i32),
                nix::sys::signal::Signal::SIGTERM,
            );
        }
    }
    drop(reg);
    Ok(())
```

- [x] **Step 2: Smoke test by hand**

Run in one terminal:
```bash
mkdir -p ~/.config/beans-daemon
printf 'beans_serve_path = "/etc/profiles/per-user/jamiebrynes/bin/beans-serve"
' > ~/.config/beans-daemon/config.toml
cargo run -- run
```
In another terminal: `pkill -TERM beansd`
Expected: clean shutdown log line, exit 0.

- [x] **Step 3: Commit**

```
git add packages/beans-daemon/src/run.rs
git commit -m 'packages/beans-daemon: SIGTERM/SIGINT graceful shutdown'
```

## Summary of Changes

Added SIGTERM/SIGINT handling to `run::run`. The shutdown `tokio::select!` now waits on `signal::unix::SignalKind::{terminate,interrupt}` alongside the UDS / HTTP server tasks; receipt logs `SIGTERM received; shutting down` (or SIGINT) and falls through to a best-effort SIGTERM sweep over all `Healthy` children's pids before returning `Ok(())`. Smoke-tested against the built binary directly (`cargo run` doesn't forward signals to the child): SIGTERM produced the expected log line and exit 0.
