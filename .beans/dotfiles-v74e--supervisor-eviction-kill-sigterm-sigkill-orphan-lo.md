---
# dotfiles-v74e
title: 'Supervisor: eviction kill (SIGTERM → SIGKILL → orphan log)'
status: todo
type: task
created_at: 2026-05-03T14:36:26Z
updated_at: 2026-05-03T14:36:26Z
parent: dotfiles-pmk6
---

**Files:**
- Modify: `packages/beans-daemon/src/supervisor.rs`

Per spec §3 + failure modes: eviction marks state `Evicting`, sends SIGTERM, waits up to 5s, sends SIGKILL on timeout, waits another 5s, drops the entry. On reap timeout: drop, log WARN with leaked pid.

- [ ] **Step 1: Write the failing test**

Append to `mod tests` in `packages/beans-daemon/src/supervisor.rs`:
```rust
    /// Child that exits cleanly on SIGTERM after a configurable delay.
    struct DelayedExitChild {
        pid: u32,
        sigterm_to_exit: Duration,
        notify: Arc<tokio::sync::Notify>,
    }
    #[async_trait]
    impl ChildHandle for DelayedExitChild {
        fn pid(&self) -> u32 { self.pid }
        async fn wait(&mut self) -> std::io::Result<String> {
            self.notify.notified().await;
            Ok("exited".into())
        }
        async fn send_sigterm(&mut self) -> std::io::Result<()> {
            let n = self.notify.clone();
            let d = self.sigterm_to_exit;
            tokio::spawn(async move { tokio::time::sleep(d).await; n.notify_one(); });
            Ok(())
        }
        async fn send_sigkill(&mut self) -> std::io::Result<()> {
            self.notify.notify_one();
            Ok(())
        }
    }

    #[tokio::test]
    async fn evict_terminates_quickly_on_sigterm() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let now = Instant::now();
        registry.lock().await.insert_spawning("/tmp/p".into(), "p".into(), now).unwrap();
        registry.lock().await.transition_state(
            &"/tmp/p".into(),
            ProjectState::Healthy { port: 1, pid: 999, spawned_at: now }
        ).unwrap();

        let child: Box<dyn ChildHandle> = Box::new(DelayedExitChild {
            pid: 999,
            sigterm_to_exit: Duration::from_millis(100),
            notify: Arc::new(tokio::sync::Notify::new()),
        });

        Supervisor::<ImmediateHealthySpawner>::evict(
            registry.clone(),
            "/tmp/p".into(),
            child,
            Duration::from_secs(2),  // sigterm grace
            Duration::from_secs(2),  // sigkill grace
        ).await;

        assert!(registry.lock().await.get(&"/tmp/p".into()).is_none());
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test supervisor::tests::evict`
Expected: FAIL — `Supervisor::evict` doesn't exist.

- [ ] **Step 3: Implement `evict` (associated fn so it can be spawned without holding `&self`)**

Add to `packages/beans-daemon/src/supervisor.rs`:
```rust
impl<S: ChildSpawner + 'static> Supervisor<S> {
    /// Background task: SIGTERM → wait → SIGKILL → wait → drop entry.
    /// Logs WARN on reap timeout (orphaned process).
    pub async fn evict(
        registry: Arc<Mutex<Registry>>,
        key: std::path::PathBuf,
        mut child: Box<dyn ChildHandle>,
        sigterm_grace: Duration,
        sigkill_grace: Duration,
    ) {
        let pid = child.pid();
        tracing::info!(?key, pid, "evicting project");

        let _ = child.send_sigterm().await;
        if tokio::time::timeout(sigterm_grace, child.wait()).await.is_ok() {
            registry.lock().await.remove(&key);
            tracing::info!(?key, pid, "evicted (clean SIGTERM exit)");
            return;
        }

        let _ = child.send_sigkill().await;
        if tokio::time::timeout(sigkill_grace, child.wait()).await.is_ok() {
            registry.lock().await.remove(&key);
            tracing::info!(?key, pid, "evicted (SIGKILL)");
            return;
        }

        registry.lock().await.remove(&key);
        tracing::warn!(?key, pid, "eviction reap timed out; orphaning process — bounded RAM cost until reboot");
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cargo test supervisor::`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/supervisor.rs
git commit -m "packages/beans-daemon: supervisor eviction with SIGTERM/SIGKILL/orphan handling"
```
