---
# dotfiles-wj32
title: 'Supervisor: child handle registry + `trigger_eviction`'
status: todo
type: task
created_at: 2026-05-03T14:45:52Z
updated_at: 2026-05-03T14:45:52Z
parent: dotfiles-pmk6
---

**Files:**
- Modify: `packages/beans-daemon/src/supervisor.rs`

The supervisor must keep child handles alive after spawn so `evict` (and `handle_stop`) have something to SIGTERM/SIGKILL. Without this, the child handle in `start_project` is dropped at function exit, leaving no way to signal the child later.

- [ ] **Step 1: Write the failing test**

Append to `mod tests` in `packages/beans-daemon/src/supervisor.rs`:
```rust
    #[tokio::test]
    async fn trigger_eviction_kills_stored_child_and_drops_entry() {
        use std::sync::atomic::{AtomicBool, Ordering};
        let registry = Arc::new(Mutex::new(Registry::new()));
        let now = Instant::now();
        registry.lock().await.insert_spawning("/tmp/p".into(), "p".into(), now).unwrap();
        registry.lock().await.transition_state(
            &"/tmp/p".into(),
            ProjectState::Healthy { port: 1, pid: 7, spawned_at: now },
        ).unwrap();

        let was_killed = Arc::new(AtomicBool::new(false));
        let killed_clone = was_killed.clone();

        struct TrackingChild { killed: Arc<AtomicBool>, notify: Arc<tokio::sync::Notify> }
        #[async_trait]
        impl ChildHandle for TrackingChild {
            fn pid(&self) -> u32 { 7 }
            async fn wait(&mut self) -> std::io::Result<String> {
                self.notify.notified().await; Ok("dead".into())
            }
            async fn send_sigterm(&mut self) -> std::io::Result<()> {
                self.killed.store(true, Ordering::SeqCst); self.notify.notify_one(); Ok(())
            }
            async fn send_sigkill(&mut self) -> std::io::Result<()> { Ok(()) }
        }

        let sup = Supervisor {
            registry: registry.clone(),
            spawner:  ImmediateHealthySpawner,  // unused here
            health_timeout: Duration::from_secs(1),
        };
        let notify = Arc::new(tokio::sync::Notify::new());
        sup.insert_child("/tmp/p".into(), Box::new(TrackingChild { killed: killed_clone, notify })).await;

        sup.trigger_eviction("/tmp/p".into(), Duration::from_secs(2), Duration::from_secs(2)).await;
        // Eviction is fire-and-forget; wait briefly for the spawned task to run.
        tokio::time::sleep(Duration::from_millis(200)).await;

        assert!(was_killed.load(Ordering::SeqCst));
        assert!(registry.lock().await.get(&"/tmp/p".into()).is_none());
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test supervisor::tests::trigger_eviction`
Expected: FAIL — `Supervisor::insert_child` and `Supervisor::trigger_eviction` don't exist.

- [ ] **Step 3: Add the child handle map and methods**

Add a field to `Supervisor`:
```rust
use std::collections::HashMap;

pub struct Supervisor<S: ChildSpawner> {
    pub registry: Arc<Mutex<Registry>>,
    pub spawner:  S,
    pub health_timeout: Duration,
    pub children: Arc<Mutex<HashMap<std::path::PathBuf, Box<dyn ChildHandle>>>>,
}
```

(All test-site constructions of `Supervisor` need a new `children: Arc::new(Mutex::new(HashMap::new()))` field. Update them.)

In `start_project`, after a successful spawn, store the handle:
```rust
        // Inside start_project, replace `let mut child = self.spawner.spawn(...).await?;`
        // and the subsequent flow with:
        let child = self.spawner.spawn(&key, port).await?;
        let pid = child.pid();
        let spawned_at = Instant::now();
        self.children.lock().await.insert(key.clone(), child);
        // ...health-check the same way as before; on failure, remove and SIGKILL:
        if Self::wait_until_healthy(port, self.health_timeout).await {
            self.registry.lock().await.transition_state(
                &key, ProjectState::Healthy { port, pid, spawned_at },
            )?;
        } else {
            if let Some(mut c) = self.children.lock().await.remove(&key) {
                let _ = c.send_sigkill().await;
            }
            self.registry.lock().await.transition_state(
                &key,
                ProjectState::Dead { reason: "startup health check timed out".into(), since: Instant::now() },
            )?;
        }
        Ok(())
```

Add `insert_child` (mostly used by tests, but also handy for restart logic):
```rust
    pub async fn insert_child(&self, key: std::path::PathBuf, child: Box<dyn ChildHandle>) {
        self.children.lock().await.insert(key, child);
    }
```

Add `trigger_eviction` — pulls the child handle, transitions registry to `Evicting`, spawns the eviction task:
```rust
    pub fn trigger_eviction(
        self: &Arc<Self>,
        key: std::path::PathBuf,
        sigterm_grace: Duration,
        sigkill_grace: Duration,
    ) {
        let me = self.clone();
        tokio::spawn(async move {
            let child = me.children.lock().await.remove(&key);
            if let Some(child) = child {
                me.registry.lock().await.transition_state(
                    &key, ProjectState::Evicting { since: Instant::now() }
                ).ok();
                Self::evict(me.registry.clone(), key, child, sigterm_grace, sigkill_grace).await;
            } else {
                tracing::warn!(?key, "trigger_eviction: no child handle stored");
                me.registry.lock().await.remove(&key);
            }
        });
    }
```

(Note: `trigger_eviction` requires `&Arc<Self>`. Callers (the `Daemon` struct in F5) hold `Arc<Supervisor<S>>`, so they can call `supervisor.trigger_eviction(...)` directly.)

- [ ] **Step 4: Run tests**

Run: `cargo test supervisor::`
Expected: all tests pass (including pre-existing ones — you may need to update test-site `Supervisor` constructions to include the `children` field).

- [ ] **Step 5: Commit**

```
git add packages/beans-daemon/src/supervisor.rs
git commit -m 'packages/beans-daemon: supervisor child handle registry + trigger_eviction'
```
