---
# dotfiles-mcs1
title: 'Supervisor: post-startup wait + auto-restart on unexpected exit'
status: todo
type: task
created_at: 2026-05-03T14:45:52Z
updated_at: 2026-05-03T14:45:52Z
parent: dotfiles-pmk6
---

**Files:**
- Modify: `packages/beans-daemon/src/supervisor.rs`

Spec §5: after a child has been marked Healthy, the supervisor must continue watching `child.wait()`. On unexpected exit, mark Dead and restart up to 3 times within 60 s (1s/4s/16s backoff). After exhausting, leave Dead.

The challenge: once we store the child handle in `self.children`, only the supervisor can call `wait()` on it. We need a long-lived watcher task per healthy child.

- [ ] **Step 1: Write the failing test**

Append to `mod tests`:
```rust
    /// Child that exits "unexpectedly" after a configurable delay.
    struct AutoExitChild {
        notify: Arc<tokio::sync::Notify>,
        exit_after: Duration,
    }
    #[async_trait]
    impl ChildHandle for AutoExitChild {
        fn pid(&self) -> u32 { 100 }
        async fn wait(&mut self) -> std::io::Result<String> {
            tokio::time::sleep(self.exit_after).await;
            self.notify.notify_one();
            Ok("crashed".into())
        }
        async fn send_sigterm(&mut self) -> std::io::Result<()> { Ok(()) }
        async fn send_sigkill(&mut self) -> std::io::Result<()> { Ok(()) }
    }

    #[tokio::test]
    async fn watch_for_exit_marks_dead_when_child_crashes() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry.lock().await.insert_spawning("/tmp/p".into(), "p".into(), Instant::now()).unwrap();
        registry.lock().await.transition_state(
            &"/tmp/p".into(),
            ProjectState::Healthy { port: 1, pid: 100, spawned_at: Instant::now() },
        ).unwrap();

        let sup = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner:  ImmediateHealthySpawner,
            health_timeout: Duration::from_secs(1),
            children: Arc::new(Mutex::new(std::collections::HashMap::new())),
        });
        let notify = Arc::new(tokio::sync::Notify::new());
        let child: Box<dyn ChildHandle> = Box::new(AutoExitChild { notify: notify.clone(), exit_after: Duration::from_millis(100) });
        sup.insert_child("/tmp/p".into(), child).await;
        sup.watch_for_exit("/tmp/p".into(), 0, Duration::from_millis(50));

        // Wait for the child to "crash" and the supervisor to react.
        tokio::time::sleep(Duration::from_millis(500)).await;

        let r = registry.lock().await;
        assert!(matches!(
            r.get(&"/tmp/p".into()).map(|p| &p.state),
            Some(ProjectState::Dead { .. })
        ));
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test supervisor::tests::watch_for_exit`
Expected: FAIL — `Supervisor::watch_for_exit` doesn't exist.

- [ ] **Step 3: Implement `watch_for_exit`**

Add to `Supervisor`:
```rust
    /// Spawn a task that awaits the stored child handle's `wait()`, then:
    ///   - marks the project Dead with the exit status as the reason,
    ///   - if `attempts_remaining > 0`, sleeps `backoff` and re-spawns,
    ///     incrementing `attempts_used` and quadrupling backoff.
    /// Caller invokes this once after a successful health-check transition.
    pub fn watch_for_exit(
        self: &Arc<Self>,
        key: std::path::PathBuf,
        attempts_used: usize,
        backoff: Duration,
    ) where S: 'static
    {
        const MAX_ATTEMPTS: usize = 3;
        const WINDOW: Duration  = Duration::from_secs(60);
        let me = self.clone();
        tokio::spawn(async move {
            // Take ownership of the handle for the duration of the wait;
            // re-insert if we end up restarting.
            let mut child = match me.children.lock().await.remove(&key) {
                Some(c) => c,
                None    => return,  // already evicted
            };
            let exit = child.wait().await.map(|s| s).unwrap_or_else(|e| format!("wait error: {e}"));
            tracing::warn!(?key, exit, attempts_used, "child exited unexpectedly");

            me.registry.lock().await.transition_state(
                &key, ProjectState::Dead { reason: exit, since: Instant::now() }
            ).ok();

            if attempts_used + 1 >= MAX_ATTEMPTS { return; }
            tokio::time::sleep(backoff).await;
            // Try restart by going through start_project_with_retries with a single attempt;
            // the registry transition back to Spawning is handled there.
            if me.start_project_with_retries(key.clone(), 1, Duration::from_millis(0)).await.is_ok() {
                // If startup succeeded, watch again with incremented count.
                me.watch_for_exit(key, attempts_used + 1, backoff * 4);
            }
            let _ = WINDOW;  // window currently informational; tighten if real flapping is observed
        });
    }
```

- [ ] **Step 4: Wire into `start_project`**

In `start_project`, after the successful `Healthy` transition (and the matching `Ok(())`), invoke:
```rust
            // Caller (cd handler) holds `Arc<Supervisor>`; it invokes watch_for_exit
            // after start_project returns. Do NOT call it from inside start_project
            // because we don't have `Arc<Self>` here. See F5.T3 wiring update.
```

(Or, refactor `start_project` to accept `&Arc<Self>` so it can chain `watch_for_exit` itself. Implementer's choice; the cd-handler-side wiring works fine.)

- [ ] **Step 5: Run tests**

Run: `cargo test supervisor::`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```
git add packages/beans-daemon/src/supervisor.rs
git commit -m 'packages/beans-daemon: supervisor post-startup wait + auto-restart'
```
