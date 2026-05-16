//! Real bind_uds + real serve(MockHandler) + real Client, one assertion per op.

use async_trait::async_trait;
use beansd_rpc::{
    CdResponse, Client, Handler, LsResponse, ProjectState, ProjectSummary, StartResponse,
    StatusResponse, bind_uds, serve,
};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use tempfile::tempdir;

struct MockHandler {
    cd_calls: AtomicUsize,
}

impl MockHandler {
    fn new() -> Self {
        Self {
            cd_calls: AtomicUsize::new(0),
        }
    }
}

#[async_trait]
impl Handler for MockHandler {
    async fn cd(&self, _cwd: PathBuf) -> anyhow::Result<CdResponse> {
        self.cd_calls.fetch_add(1, Ordering::SeqCst);
        Ok(CdResponse::NotRegistered)
    }
    async fn ls(&self) -> anyhow::Result<LsResponse> {
        Ok(LsResponse {
            projects: vec![ProjectSummary {
                key: PathBuf::from("/p"),
                display_name: "p".into(),
                state: ProjectState::Healthy,
                port: Some(4242),
            }],
        })
    }
    async fn start(&self, _: PathBuf) -> anyhow::Result<StartResponse> {
        Ok(StartResponse::AlreadyActive)
    }
    async fn stop(&self, key: PathBuf) -> anyhow::Result<()> {
        if key == Path::new("/missing") {
            anyhow::bail!("unknown project: /missing");
        }
        Ok(())
    }
    async fn status(&self) -> anyhow::Result<StatusResponse> {
        Ok(StatusResponse {
            registry_size: 1,
            active: 1,
            lru_cap: 8,
        })
    }
    async fn heartbeat(&self, _: PathBuf) -> anyhow::Result<()> {
        Ok(())
    }
}

async fn boot() -> (PathBuf, tempfile::TempDir, Arc<MockHandler>) {
    let dir = tempdir().unwrap();
    let p = dir.path().join("sock");
    let listener = bind_uds(&p).unwrap();
    let handler = Arc::new(MockHandler::new());
    let h = handler.clone();
    tokio::spawn(async move { serve(listener, h).await });
    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    (p, dir, handler)
}

#[tokio::test]
async fn cd_round_trip() {
    let (p, _dir, handler) = boot().await;
    let p2 = p.clone();
    tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.cd(PathBuf::from("/some/dir")).unwrap();
    })
    .await
    .unwrap();
    // Tiny delay so the daemon-side dispatch task observes the call.
    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    assert_eq!(handler.cd_calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn ls_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.ls().unwrap()
    })
    .await
    .unwrap();
    assert_eq!(resp.projects.len(), 1);
    assert_eq!(resp.projects[0].port, Some(4242));
}

#[tokio::test]
async fn start_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.start(PathBuf::from("/p")).unwrap()
    })
    .await
    .unwrap();
    assert_eq!(resp, StartResponse::AlreadyActive);
}

#[tokio::test]
async fn stop_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let result = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.stop(PathBuf::from("/p"))
    })
    .await
    .unwrap();
    assert!(result.is_ok());
}

#[tokio::test]
async fn status_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.status().unwrap()
    })
    .await
    .unwrap();
    assert_eq!(resp.lru_cap, 8);
}

#[tokio::test]
async fn heartbeat_round_trip() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let result = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.heartbeat(PathBuf::from("/p"))
    })
    .await
    .unwrap();
    assert!(result.is_ok());
}

#[tokio::test]
async fn handler_err_surfaces_with_rpc_context() {
    let (p, _dir, _h) = boot().await;
    let p2 = p.clone();
    let err = tokio::task::spawn_blocking(move || {
        let c = Client::connect_to(p2).unwrap();
        c.stop(PathBuf::from("/missing"))
    })
    .await
    .unwrap()
    .unwrap_err();
    assert!(format!("{err:#}").contains("rpc stop"));
    assert!(format!("{err:#}").contains("unknown project"));
}
