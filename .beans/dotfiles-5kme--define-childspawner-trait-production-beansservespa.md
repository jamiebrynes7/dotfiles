---
# dotfiles-5kme
title: Define `ChildSpawner` trait + production `BeansServeSpawner`
status: todo
type: task
created_at: 2026-05-03T14:36:26Z
updated_at: 2026-05-03T14:36:26Z
parent: dotfiles-pmk6
---

**Files:**
- Create: `packages/beans-daemon/src/spawner.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod spawner;`)

Abstracting child spawning behind a trait lets the supervisor be tested with an in-process mock instead of needing a fake `beans-serve` binary on disk.

- [ ] **Step 1: Write the failing test (with mock impl)**

Create `packages/beans-daemon/src/spawner.rs`:
```rust
use async_trait::async_trait;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

/// A handle the supervisor uses to interact with a running child.
/// Production impl wraps `tokio::process::Child`; mocks can return whatever.
#[async_trait]
pub trait ChildHandle: Send + Sync {
    fn pid(&self) -> u32;
    /// Wait for the process to exit. Returns the exit status as a string
    /// (we only need it for logging — typed status would be over-modelling).
    async fn wait(&mut self) -> std::io::Result<String>;
    async fn send_sigterm(&mut self) -> std::io::Result<()>;
    async fn send_sigkill(&mut self) -> std::io::Result<()>;
}

#[async_trait]
pub trait ChildSpawner: Send + Sync {
    /// Spawn a child for the given project on the given port.
    async fn spawn(&self, beans_yml_dir: &Path, port: u16) -> anyhow::Result<Box<dyn ChildHandle>>;
}

/// Production spawner: exec's `beans-serve serve --port <port> --beans-path <dir>`.
pub struct BeansServeSpawner {
    pub binary: std::path::PathBuf,
}

#[async_trait]
impl ChildSpawner for BeansServeSpawner {
    async fn spawn(&self, beans_yml_dir: &Path, port: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
        let child = tokio::process::Command::new(&self.binary)
            .arg("serve")
            .arg("--port").arg(port.to_string())
            .arg("--beans-path").arg(beans_yml_dir)
            .stdin(std::process::Stdio::null())
            // inherit stdout/stderr so child logs land in the daemon's log
            .kill_on_drop(false)
            .spawn()?;
        Ok(Box::new(BeansServeChild { inner: Arc::new(Mutex::new(child)) }))
    }
}

struct BeansServeChild {
    inner: Arc<Mutex<tokio::process::Child>>,
}

#[async_trait]
impl ChildHandle for BeansServeChild {
    fn pid(&self) -> u32 {
        // safe to block-lock in a sync method; only contended at signal time
        self.inner.try_lock().ok().and_then(|c| c.id()).unwrap_or(0)
    }
    async fn wait(&mut self) -> std::io::Result<String> {
        let status = self.inner.lock().await.wait().await?;
        Ok(status.to_string())
    }
    async fn send_sigterm(&mut self) -> std::io::Result<()> {
        if let Some(pid) = self.inner.lock().await.id() {
            let _ = nix::sys::signal::kill(
                nix::unistd::Pid::from_raw(pid as i32),
                nix::sys::signal::Signal::SIGTERM,
            );
        }
        Ok(())
    }
    async fn send_sigkill(&mut self) -> std::io::Result<()> {
        if let Some(pid) = self.inner.lock().await.id() {
            let _ = nix::sys::signal::kill(
                nix::unistd::Pid::from_raw(pid as i32),
                nix::sys::signal::Signal::SIGKILL,
            );
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn beans_serve_spawner_errors_on_missing_binary() {
        let s = BeansServeSpawner { binary: "/no/such/binary".into() };
        let res = s.spawn(Path::new("/tmp"), 1).await;
        assert!(res.is_err());
    }
}
```

Add to `Cargo.toml` `[dependencies]`:
```toml
async-trait = "0.1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test spawner::`
Expected: FAIL — `mod spawner` not declared (and `async-trait` not in deps).

- [ ] **Step 3: Wire it up**

Add `mod spawner;` to `packages/beans-daemon/src/main.rs` and `async-trait` to `Cargo.toml`.

- [ ] **Step 4: Run tests**

Run: `cargo test spawner::`
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/spawner.rs packages/beans-daemon/src/main.rs packages/beans-daemon/Cargo.toml packages/beans-daemon/Cargo.lock
git commit -m "packages/beans-daemon: ChildSpawner trait + BeansServeSpawner impl"
```
