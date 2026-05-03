---
# dotfiles-5q83
title: 'Supervisor: spawn + health-check loop'
status: todo
type: task
created_at: 2026-05-03T14:36:26Z
updated_at: 2026-05-03T14:36:26Z
parent: dotfiles-pmk6
---

**Files:**
- Create: `packages/beans-daemon/src/supervisor.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod supervisor;`)

The supervisor owns one project's lifecycle. It is given the registry handle and a spawner. On `start_project` it picks a port, calls `spawner.spawn`, polls `GET http://127.0.0.1:<port>/` until 200 or 5s timeout, then transitions the registry entry to `Healthy` or `Dead`.

- [ ] **Step 1: Write the failing test (with mock spawner)**

Create `packages/beans-daemon/src/supervisor.rs`:
```rust
use crate::registry::{ProjectState, Registry};
use crate::spawner::{ChildHandle, ChildSpawner};
use async_trait::async_trait;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

pub struct Supervisor<S: ChildSpawner> {
    pub registry: Arc<Mutex<Registry>>,
    pub spawner:  S,
    /// Health-check timeout for child startup.
    pub health_timeout: Duration,
}

impl<S: ChildSpawner + 'static> Supervisor<S> {
    /// Spawn a child for `key`, wait for health, transition registry state.
    /// Caller is responsible for having already inserted a `Spawning` entry
    /// for the key (so the cap accounting is correct from cd-op's POV).
    pub async fn start_project(&self, key: std::path::PathBuf) -> anyhow::Result<()> {
        let port = crate::port_alloc::pick_loopback_port()?;
        let mut child = self.spawner.spawn(&key, port).await?;
        let pid = child.pid();
        let spawned_at = Instant::now();

        if Self::wait_until_healthy(port, self.health_timeout).await {
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Healthy { port, pid, spawned_at },
            )?;
        } else {
            let _ = child.send_sigkill().await;
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Dead { reason: "startup health check timed out".into(), since: Instant::now() },
            )?;
        }
        Ok(())
    }

    async fn wait_until_healthy(port: u16, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;
        let url = format!("http://127.0.0.1:{port}/");
        loop {
            if Instant::now() >= deadline { return false; }
            if let Ok(resp) = reqwest::get(&url).await {
                if resp.status().is_success() { return true; }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mock spawner that immediately starts an in-process axum responding 200.
    struct ImmediateHealthySpawner;
    #[async_trait]
    impl ChildSpawner for ImmediateHealthySpawner {
        async fn spawn(&self, _dir: &Path, port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
            // Bind a real listener on the given port and serve 200 OK forever.
            let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
            tokio::spawn(async move {
                use axum::routing::get;
                let app = axum::Router::new().route("/", get(|| async { "ok" }));
                axum::serve(listener, app).await.ok();
            });
            Ok(Box::new(MockChild { pid: 12345 }))
        }
    }

    struct MockChild { pid: u32 }
    #[async_trait]
    impl ChildHandle for MockChild {
        fn pid(&self) -> u32 { self.pid }
        async fn wait(&mut self) -> std::io::Result<String> {
            std::future::pending().await  // never exits
        }
        async fn send_sigterm(&mut self) -> std::io::Result<()> { Ok(()) }
        async fn send_sigkill(&mut self) -> std::io::Result<()> { Ok(()) }
    }

    #[tokio::test]
    async fn start_project_marks_healthy_when_child_responds() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry.lock().await.insert_spawning(
            "/tmp/proj".into(), "proj".into(), Instant::now()
        ).unwrap();

        let sup = Supervisor {
            registry: registry.clone(),
            spawner:  ImmediateHealthySpawner,
            health_timeout: Duration::from_secs(2),
        };
        sup.start_project("/tmp/proj".into()).await.unwrap();

        let r = registry.lock().await;
        let p = r.get(&"/tmp/proj".into()).unwrap();
        assert!(matches!(p.state, ProjectState::Healthy { .. }));
    }
}
```

Add to `Cargo.toml` `[dependencies]`:
```toml
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls"] }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test supervisor::`
Expected: FAIL — `mod supervisor` not declared.

- [ ] **Step 3: Wire it up**

Add `mod supervisor;` and the `reqwest` dep.

- [ ] **Step 4: Run tests**

Run: `cargo test supervisor::start_project_marks_healthy_when_child_responds`
Expected: PASS within ~2 s.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/supervisor.rs packages/beans-daemon/src/main.rs packages/beans-daemon/Cargo.toml packages/beans-daemon/Cargo.lock
git commit -m "packages/beans-daemon: supervisor spawn + health check"
```
