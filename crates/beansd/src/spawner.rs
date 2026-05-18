use async_trait::async_trait;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

use nix::sys::signal;
use nix::unistd::Pid;

/// A handle the supervisor uses to interact with a running child.
/// Production impl wraps `tokio::process::Child`; mocks can return whatever.
#[async_trait]
pub trait ChildHandle: Send + Sync {
    fn pid(&self) -> u32;
    async fn wait(&mut self) -> std::io::Result<String>;
    async fn kill(&mut self) -> std::io::Result<()>;
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
            .arg("--port")
            .arg(port.to_string())
            .stdin(std::process::Stdio::null())
            .current_dir(beans_yml_dir)
            .kill_on_drop(false)
            .spawn()?;
        Ok(Box::new(BeansServeChild {
            inner: Arc::new(Mutex::new(child)),
        }))
    }
}

struct BeansServeChild {
    inner: Arc<Mutex<tokio::process::Child>>,
}

#[async_trait]
impl ChildHandle for BeansServeChild {
    fn pid(&self) -> u32 {
        self.inner.try_lock().ok().and_then(|c| c.id()).unwrap_or(0)
    }

    async fn wait(&mut self) -> std::io::Result<String> {
        let status = self.inner.lock().await.wait().await?;
        Ok(status.to_string())
    }

    async fn kill(&mut self) -> std::io::Result<()> {
        let pid = match self.inner.lock().await.id() {
            Some(p) => p,
            None => return Ok(()),
        };
        let nix_pid = Pid::from_raw(pid as i32);

        tracing::info!(?pid, "sending SIGTERM to process");
        signal::kill(nix_pid, signal::SIGTERM)?;

        let timeout = Duration::from_secs(3);
        match tokio::time::timeout(timeout, self.wait()).await {
            Ok(r) => match r {
                Ok(_) => return Ok(()),
                Err(e) => {
                    tracing::error!(?e, "unable to wait for child process exit");
                    return Err(e);
                }
            },
            Err(_) => tracing::warn!(?pid, "process did not respond to SIGTERM in time"),
        };

        signal::kill(nix_pid, signal::SIGKILL)?;
        match tokio::time::timeout(timeout, self.wait()).await {
            Ok(r) => match r {
                Ok(_) => return Ok(()),
                Err(e) => {
                    tracing::error!(?e, "unable to wait for child process exit");
                    return Err(e);
                }
            },
            Err(_) => tracing::warn!(?pid, "process did not respond to SIGKILL in time"),
        }

        Err(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            anyhow::anyhow!("process did not exit in time"),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn beans_serve_spawner_errors_on_missing_binary() {
        let s = BeansServeSpawner {
            binary: "/no/such/binary".into(),
        };
        let res = s.spawn(Path::new("/tmp"), 1).await;
        assert!(res.is_err());
    }
}

#[cfg(test)]
pub mod testing {
    use axum::async_trait;
    use std::{path::Path, sync::Arc};
    use tokio::sync::{Mutex, SetOnce};

    use super::{ChildHandle, ChildSpawner};

    #[derive(Clone)]
    pub struct FakeChildHandle {
        pid: u32,
        is_ended: Arc<SetOnce<()>>,
    }

    impl FakeChildHandle {
        pub fn new(pid: u32) -> Self {
            FakeChildHandle {
                pid,
                is_ended: Arc::new(SetOnce::new()),
            }
        }
    }

    #[async_trait]
    impl ChildHandle for FakeChildHandle {
        fn pid(&self) -> u32 {
            self.pid
        }
        async fn wait(&mut self) -> std::io::Result<String> {
            self.is_ended.wait().await;
            Ok("exited".into())
        }

        async fn kill(&mut self) -> std::io::Result<()> {
            self.is_ended.set(()).map_err(|_| {
                std::io::Error::other(anyhow::anyhow!("child process already dead"))
            })?;
            Ok(())
        }
    }

    pub struct FakeSpawner {
        children: Mutex<Vec<FakeChildHandle>>,
    }

    impl FakeSpawner {
        pub fn new() -> Self {
            FakeSpawner {
                children: Mutex::new(Vec::new()),
            }
        }

        pub async fn children(&self) -> Vec<FakeChildHandle> {
            self.children.lock().await.clone()
        }
    }

    #[async_trait]
    impl ChildSpawner for FakeSpawner {
        async fn spawn(&self, _: &Path, _: u16) -> anyhow::Result<Box<dyn ChildHandle>> {
            let child = FakeChildHandle::new(1);
            self.children.lock().await.push(child.clone());
            Ok(Box::new(child))
        }
    }
}
