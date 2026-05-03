---
# dotfiles-1dhn
title: 'Op dispatcher: ls, start, stop, status, heartbeat handlers'
status: todo
type: task
priority: normal
created_at: 2026-05-03T14:38:16Z
updated_at: 2026-05-03T14:48:55Z
parent: dotfiles-2ecf
---

**Files:**
- Modify: `packages/beans-daemon/src/control.rs`

- [ ] **Step 1: Write the test**

Append to `packages/beans-daemon/src/control.rs`:
```rust
impl<S: ChildSpawner + 'static> Daemon<S> {
    pub async fn handle_ls(&self) -> serde_json::Value {
        let reg = self.registry.lock().await;
        let projects: Vec<_> = reg.iter().map(|p| {
            let (state_label, port) = match &p.state {
                crate::registry::ProjectState::Spawning { .. } => ("spawning", None),
                crate::registry::ProjectState::Healthy  { port, .. } => ("healthy", Some(*port)),
                crate::registry::ProjectState::Evicting { .. } => ("evicting", None),
                crate::registry::ProjectState::Dead     { .. } => ("dead", None),
            };
            serde_json::json!({
                "key": p.key,
                "display_name": p.display_name,
                "state": state_label,
                "port": port,
            })
        }).collect();
        serde_json::json!({ "projects": projects })
    }

    pub async fn handle_status(&self) -> serde_json::Value {
        let reg = self.registry.lock().await;
        serde_json::json!({
            "registry_size": reg.iter().count(),
            "active":        reg.count_active(),
            "lru_cap":       self.lru_cap,
        })
    }

    pub async fn handle_heartbeat(&self, key: std::path::PathBuf) -> serde_json::Value {
        self.registry.lock().await.bump_last_used(&key, Instant::now());
        serde_json::json!({ "bumped": true })
    }

    pub async fn handle_stop(&self, key: std::path::PathBuf) -> serde_json::Value {
        // Stop = trigger eviction (SIGTERM/SIGKILL/drop). The eviction task
        // transitions the project to Evicting and removes it from the registry
        // on completion. handle_stop returns immediately.
        let exists = self.registry.lock().await.get(&key).is_some();
        if !exists {
            return serde_json::json!({ "stopped": false, "error": "unknown project" });
        }
        self.supervisor.trigger_eviction(key, self.sigterm_grace, self.sigkill_grace);
        serde_json::json!({ "stopped": true })
    }

    pub async fn handle_start(&self, key: std::path::PathBuf) -> serde_json::Value {
        // Re-spawn a Dead project. If currently active, no-op success.
        let now = Instant::now();
        let mut reg = self.registry.lock().await;
        match reg.get(&key).map(|p| &p.state) {
            Some(crate::registry::ProjectState::Healthy { .. } | crate::registry::ProjectState::Spawning { .. }) => {
                return serde_json::json!({ "started": true, "action": "already_active" });
            }
            Some(_) => {
                let _ = reg.transition_state(&key, crate::registry::ProjectState::Spawning { since: now });
            }
            None => {
                return serde_json::json!({ "started": false, "error": "unknown project" });
            }
        }
        drop(reg);
        let sup = self.supervisor.clone();
        let max = self.start_max_attempts;
        let backoff = self.start_base_backoff;
        let key_clone = key.clone();
        tokio::spawn(async move {
            if let Err(e) = sup.start_project_with_retries(key_clone, max, backoff).await {
                tracing::error!(?e, "start_project failed");
            }
        });
        serde_json::json!({ "started": true, "action": "spawning" })
    }
}

#[cfg(test)]
mod handler_tests {
    use super::*;
    use super::cd_tests::*;
    // Ls/status are pure registry reads; trivial smoke test only.

    #[tokio::test]
    async fn ls_returns_empty_projects_array() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner:  ImmediateHealthy,
            health_timeout: Duration::from_secs(1),
        });
        let d = Daemon {
            registry, supervisor, lru_cap: 8,
            sigterm_grace: Duration::from_secs(5),
            sigkill_grace: Duration::from_secs(5),
            start_max_attempts: 1,
            start_base_backoff: Duration::from_millis(10),
        };
        let r = d.handle_ls().await;
        assert_eq!(r["projects"].as_array().unwrap().len(), 0);
    }

    #[tokio::test]
    async fn heartbeat_bumps_last_used() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry.lock().await.insert_spawning("/tmp/x".into(), "x".into(), Instant::now()).unwrap();
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner:  ImmediateHealthy,
            health_timeout: Duration::from_secs(1),
        });
        let d = Daemon {
            registry: registry.clone(), supervisor, lru_cap: 8,
            sigterm_grace: Duration::from_secs(5),
            sigkill_grace: Duration::from_secs(5),
            start_max_attempts: 1,
            start_base_backoff: Duration::from_millis(10),
        };
        let before = registry.lock().await.get(&"/tmp/x".into()).unwrap().last_used;
        tokio::time::sleep(Duration::from_millis(20)).await;
        d.handle_heartbeat("/tmp/x".into()).await;
        let after = registry.lock().await.get(&"/tmp/x".into()).unwrap().last_used;
        assert!(after > before);
    }
}
```

To make the `cd_tests::ImmediateHealthy` and `NoOpChild` reachable from `handler_tests`, change `mod cd_tests {` to `mod cd_tests; pub mod cd_tests_pub { pub use super::cd_tests::*; }` — or simpler: declare these mocks once in `mod test_support` at the file's bottom (visible to all `#[cfg(test)] mod ...`). Pick whichever fits Rust's visibility rules cleanly.

- [ ] **Step 2: Run tests**

Run: `cargo test control::handler_tests`
Expected: 2 new tests pass.

- [ ] **Step 3: Commit**

```bash
git add packages/beans-daemon/src/control.rs
git commit -m "packages/beans-daemon: ls/start/stop/status/heartbeat op handlers"
```
