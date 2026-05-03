---
# dotfiles-qlj3
title: 'Supervisor: restart-on-crash with exponential backoff'
status: todo
type: task
created_at: 2026-05-03T14:36:26Z
updated_at: 2026-05-03T14:36:26Z
parent: dotfiles-pmk6
---

**Files:**
- Modify: `packages/beans-daemon/src/supervisor.rs`

Per spec §5: when a child exits unexpectedly, restart up to 3 times within 60 s with backoff 1s/4s/16s. After exhausting retries, leave the project `Dead`.

- [ ] **Step 1: Write the failing test**

Append to `mod tests` in `packages/beans-daemon/src/supervisor.rs`:
```rust
    /// Mock spawner whose first 2 spawns exit immediately; the 3rd stays healthy.
    struct FlakySpawner {
        spawn_count: Arc<std::sync::atomic::AtomicUsize>,
    }
    #[async_trait]
    impl ChildSpawner for FlakySpawner {
        async fn spawn(&self, _dir: &Path, port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
            let n = self.spawn_count.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            if n < 2 {
                Ok(Box::new(MockChild { pid: 1 }))  // pretends alive but no listener
            } else {
                let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
                tokio::spawn(async move {
                    use axum::routing::get;
                    let app = axum::Router::new().route("/", get(|| async { "ok" }));
                    axum::serve(listener, app).await.ok();
                });
                Ok(Box::new(MockChild { pid: 2 }))
            }
        }
    }

    #[tokio::test]
    async fn start_project_with_retries_eventually_succeeds() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry.lock().await.insert_spawning(
            "/tmp/proj".into(), "proj".into(), Instant::now()
        ).unwrap();
        let count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let sup = Supervisor {
            registry: registry.clone(),
            spawner:  FlakySpawner { spawn_count: count.clone() },
            health_timeout: Duration::from_millis(500),
        };
        // Use a fast backoff for the test.
        sup.start_project_with_retries("/tmp/proj".into(), 3, Duration::from_millis(50)).await.unwrap();

        assert_eq!(count.load(std::sync::atomic::Ordering::SeqCst), 3);
        let r = registry.lock().await;
        assert!(matches!(r.get(&"/tmp/proj".into()).unwrap().state, ProjectState::Healthy { .. }));
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test supervisor::tests::start_project_with_retries`
Expected: FAIL — `start_project_with_retries` doesn't exist.

- [ ] **Step 3: Implement the retry wrapper**

Add to `impl<S: ChildSpawner + 'static> Supervisor<S>`:
```rust
    /// Wrapper around `start_project` that retries up to `max_attempts` times
    /// with `base_backoff` * 4^n delay between attempts (1s, 4s, 16s for default 1s).
    pub async fn start_project_with_retries(
        &self,
        key: std::path::PathBuf,
        max_attempts: usize,
        base_backoff: Duration,
    ) -> anyhow::Result<()> {
        let mut backoff = base_backoff;
        for attempt in 0..max_attempts {
            // Reset state to Spawning before each attempt.
            self.registry.lock().await.transition_state(
                &key, ProjectState::Spawning { since: Instant::now() }
            )?;
            self.start_project(key.clone()).await?;
            let healthy = matches!(
                self.registry.lock().await.get(&key).map(|p| &p.state),
                Some(ProjectState::Healthy { .. })
            );
            if healthy { return Ok(()); }
            if attempt + 1 < max_attempts {
                tracing::warn!(?key, attempt = attempt + 1, ?backoff, "child startup failed; backing off");
                tokio::time::sleep(backoff).await;
                backoff *= 4;
            }
        }
        // The final start_project already left state = Dead; nothing more to do.
        Ok(())
    }
```

- [ ] **Step 4: Run tests**

Run: `cargo test supervisor::`
Expected: all tests pass within ~5 s.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/supervisor.rs
git commit -m "packages/beans-daemon: supervisor retry-on-crash with backoff"
```
