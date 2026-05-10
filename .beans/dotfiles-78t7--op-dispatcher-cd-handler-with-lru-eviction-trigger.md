---
# dotfiles-78t7
title: 'Op dispatcher: cd handler with LRU eviction trigger'
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:38:16Z
updated_at: 2026-05-10T13:42:01Z
parent: dotfiles-2ecf
---

**Files:**
- Modify: `packages/beans-daemon/src/control.rs`

The cd handler is the heart of the daemon. It:

1. Resolves the project key via `project_key::resolve`. No marker → reply with `{ok:true, data:{registered:false}}`, do nothing.
2. If already registered → bumps `last_used`, replies success.
3. If not registered:
   a. If at cap, picks LRU candidate, transitions it to `Evicting`, spawns the eviction kill on a tokio task.
   b. Inserts a fresh `Spawning` entry, transitions LRU bookkeeping for new entry.
   c. Spawns a tokio task running `Supervisor::start_project_with_retries`.
   d. Replies success immediately (the supervisor's task continues in background).

- [x] **Step 1: Write the test**

Append to `packages/beans-daemon/src/control.rs`:
```rust
use crate::registry::Registry;
use crate::spawner::ChildSpawner;
use crate::supervisor::Supervisor;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

pub struct Daemon<S: ChildSpawner + 'static> {
    pub registry: Arc<Mutex<Registry>>,
    pub supervisor: Arc<Supervisor<S>>,
    pub lru_cap: usize,
    pub sigterm_grace: Duration,
    pub sigkill_grace: Duration,
    pub start_max_attempts: usize,
    pub start_base_backoff: Duration,
}

impl<S: ChildSpawner + 'static> Daemon<S> {
    /// Handle a `cd` op. See feature description for the algorithm.
    pub async fn handle_cd(&self, cwd: std::path::PathBuf) -> serde_json::Value {
        let now = Instant::now();
        let key = match crate::project_key::resolve(&cwd) {
            Ok(Some(k))  => k,
            Ok(None)     => return serde_json::json!({ "registered": false }),
            Err(e)       => return serde_json::json!({ "registered": false, "error": e.to_string() }),
        };

        let mut reg = self.registry.lock().await;
        if reg.get(&key).is_some() {
            reg.bump_last_used(&key, now);
            return serde_json::json!({ "registered": true, "key": key, "action": "bumped" });
        }

        // Not registered. Trigger eviction if we're at the cap; the eviction
        // task transitions the project to Evicting and removes it from the
        // registry on completion. We briefly hold (cap + 1) entries until then.
        if reg.count_active() >= self.lru_cap {
            if let Some(lru_key) = reg.find_lru_for_eviction() {
                self.supervisor.trigger_eviction(lru_key, self.sigterm_grace, self.sigkill_grace);
            }
        }

        let display = key.file_name().and_then(|s| s.to_str()).unwrap_or("").to_string();
        let _ = reg.insert_spawning(key.clone(), display, now);
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

        serde_json::json!({ "registered": true, "key": key, "action": "spawned" })
    }
}

#[cfg(test)]
mod cd_tests {
    use super::*;
    use crate::spawner::{ChildHandle, BeansServeSpawner};
    use async_trait::async_trait;

    // Reuse the spawner pattern from supervisor tests by copy-paste — keep
    // the test self-contained and avoid pub(crate) on test-only items.

    struct ImmediateHealthy;
    #[async_trait]
    impl ChildSpawner for ImmediateHealthy {
        async fn spawn(&self, _dir: &std::path::Path, port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
            let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
            tokio::spawn(async move {
                use axum::routing::get;
                let app = axum::Router::new().route("/", get(|| async { "ok" }));
                axum::serve(listener, app).await.ok();
            });
            Ok(Box::new(NoOpChild))
        }
    }
    struct NoOpChild;
    #[async_trait]
    impl ChildHandle for NoOpChild {
        fn pid(&self) -> u32 { 1 }
        async fn wait(&mut self) -> std::io::Result<String> { std::future::pending().await }
        async fn send_sigterm(&mut self) -> std::io::Result<()> { Ok(()) }
        async fn send_sigkill(&mut self) -> std::io::Result<()> { Ok(()) }
    }

    #[tokio::test]
    async fn cd_into_dir_without_marker_reports_not_registered() {
        use tempfile::tempdir;
        let dir = tempdir().unwrap();
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
        let resp = d.handle_cd(dir.path().to_path_buf()).await;
        assert_eq!(resp["registered"], false);
    }

    #[tokio::test]
    async fn cd_into_marked_dir_spawns_and_registers() {
        use tempfile::tempdir;
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join(".beans.yml"), "").unwrap();
        let registry = Arc::new(Mutex::new(Registry::new()));
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner:  ImmediateHealthy,
            health_timeout: Duration::from_secs(2),
        });
        let d = Daemon {
            registry: registry.clone(), supervisor, lru_cap: 8,
            sigterm_grace: Duration::from_secs(5),
            sigkill_grace: Duration::from_secs(5),
            start_max_attempts: 1,
            start_base_backoff: Duration::from_millis(10),
        };
        let resp = d.handle_cd(dir.path().to_path_buf()).await;
        assert_eq!(resp["registered"], true);
        assert_eq!(resp["action"], "spawned");

        // give the background spawn a beat to complete
        tokio::time::sleep(Duration::from_millis(500)).await;
        let r = registry.lock().await;
        let canonical = std::fs::canonicalize(dir.path()).unwrap();
        assert!(matches!(r.get(&canonical).unwrap().state, crate::registry::ProjectState::Healthy { .. }));
    }
}
```

- [x] **Step 2: Run tests**

Run: `cargo test control::cd_tests`
Expected: both pass within ~2 s.

- [x] **Step 3: Commit**

```bash
git add packages/beans-daemon/src/control.rs
git commit -m "packages/beans-daemon: cd op handler with LRU eviction trigger"
```

## Summary of Changes

Added `Daemon<S: ChildSpawner>` to `control.rs` with the `handle_cd` op. Resolves the project key via `project_key::resolve`; on no marker → `{registered: false}`; on already-registered → bumps `last_used`, replies `{action: "bumped"}`; otherwise inserts a `Spawning` entry, kicks `Supervisor::trigger_eviction` for the LRU when at cap, spawns `start_project_with_retries` on a tokio task, and replies `{action: "spawned"}` immediately. Test fixtures (`ImmediateHealthy`, `NoOpChild`, `build_daemon`) live in a `cd_tests` module so the next task can reuse them. Two tests cover the no-marker path and the spawn-and-register path (asserts `Healthy` after the supervisor task completes).
