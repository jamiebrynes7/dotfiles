use crate::types::{CdResponse, LsResponse, StartResponse, StatusResponse};
use crate::wire::{WireRequest, WireResponse};
use async_trait::async_trait;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

#[async_trait]
pub trait Handler: Send + Sync + 'static {
    async fn cd(&self, cwd: PathBuf) -> anyhow::Result<CdResponse>;
    async fn ls(&self) -> anyhow::Result<LsResponse>;
    async fn start(&self, key: PathBuf) -> anyhow::Result<StartResponse>;
    async fn stop(&self, key: PathBuf) -> anyhow::Result<()>;
    async fn status(&self) -> anyhow::Result<StatusResponse>;
    async fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()>;
}

pub async fn serve<H: Handler>(listener: UnixListener, handler: Arc<H>) -> anyhow::Result<()> {
    loop {
        let (sock, _addr) = listener.accept().await?;
        let h = handler.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_connection(sock, h).await {
                tracing::warn!(error = ?e, "UDS connection ended with error");
            }
        });
    }
}

async fn handle_connection<H: Handler>(sock: UnixStream, handler: Arc<H>) -> anyhow::Result<()> {
    let (rd, mut wr) = sock.into_split();
    let mut lines = BufReader::new(rd).lines();
    while let Some(line) = lines.next_line().await? {
        let req: WireRequest = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let resp = WireResponse::err(format!("bad request: {e}"));
                let mut buf = serde_json::to_vec(&resp)?;
                buf.push(b'\n');
                let _ = wr.write_all(&buf).await;
                continue;
            }
        };
        let resp = dispatch(handler.as_ref(), req).await;
        let mut buf = serde_json::to_vec(&resp)?;
        buf.push(b'\n');
        // Client may have closed the read half (fire-and-forget cd); best-effort write.
        let _ = wr.write_all(&buf).await;
    }
    Ok(())
}

async fn dispatch<H: Handler>(handler: &H, req: WireRequest) -> WireResponse {
    let result: anyhow::Result<serde_json::Value> = match req {
        WireRequest::Cd { cwd } => handler.cd(cwd).await.and_then(to_value),
        WireRequest::Ls {} => handler.ls().await.and_then(to_value),
        WireRequest::Start { key } => handler.start(key).await.and_then(to_value),
        WireRequest::Stop { key } => handler.stop(key).await.and_then(to_value),
        WireRequest::Status {} => handler.status().await.and_then(to_value),
        WireRequest::Heartbeat { key } => handler.heartbeat(key).await.and_then(to_value),
    };
    match result {
        Ok(data) => WireResponse::ok(data),
        Err(e) => WireResponse::err(format!("{e:#}")),
    }
}

fn to_value<T: serde::Serialize>(t: T) -> anyhow::Result<serde_json::Value> {
    serde_json::to_value(t).map_err(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::socket::bind_uds;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tempfile::tempdir;
    use tokio::net::UnixStream as ClientStream;

    /// Records call counts and lets tests force a failure on the next op.
    struct MockHandler {
        cd_calls: AtomicUsize,
        ls_calls: AtomicUsize,
        fail_next: AtomicUsize,
    }

    impl MockHandler {
        fn new() -> Self {
            Self {
                cd_calls: AtomicUsize::new(0),
                ls_calls: AtomicUsize::new(0),
                fail_next: AtomicUsize::new(0),
            }
        }
        fn check_fail(&self) -> Option<anyhow::Error> {
            let prev = self.fail_next.load(Ordering::SeqCst);
            if prev > 0 {
                self.fail_next.store(prev - 1, Ordering::SeqCst);
                Some(anyhow::anyhow!("mock failure"))
            } else {
                None
            }
        }
    }

    #[async_trait]
    impl Handler for MockHandler {
        async fn cd(&self, _cwd: PathBuf) -> anyhow::Result<CdResponse> {
            self.cd_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(e) = self.check_fail() {
                return Err(e);
            }
            Ok(CdResponse::NotRegistered)
        }
        async fn ls(&self) -> anyhow::Result<LsResponse> {
            self.ls_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(e) = self.check_fail() {
                return Err(e);
            }
            Ok(LsResponse { projects: vec![] })
        }
        async fn start(&self, _: PathBuf) -> anyhow::Result<StartResponse> {
            if let Some(e) = self.check_fail() {
                return Err(e);
            }
            Ok(StartResponse::Spawning)
        }
        async fn stop(&self, _: PathBuf) -> anyhow::Result<()> {
            if let Some(e) = self.check_fail() {
                return Err(e);
            }
            Ok(())
        }
        async fn status(&self) -> anyhow::Result<StatusResponse> {
            if let Some(e) = self.check_fail() {
                return Err(e);
            }
            Ok(StatusResponse {
                registry_size: 0,
                active: 0,
                lru_cap: 8,
            })
        }
        async fn heartbeat(&self, _: PathBuf) -> anyhow::Result<()> {
            if let Some(e) = self.check_fail() {
                return Err(e);
            }
            Ok(())
        }
    }

    async fn raw_round_trip(sock_path: &std::path::Path, request_line: &str) -> String {
        let mut sock = ClientStream::connect(sock_path).await.unwrap();
        sock.write_all(request_line.as_bytes()).await.unwrap();
        sock.flush().await.unwrap();
        let mut lines = BufReader::new(sock).lines();
        lines.next_line().await.unwrap().unwrap()
    }

    #[tokio::test]
    async fn dispatches_ls_to_handler() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let line = raw_round_trip(&p, "{\"op\":\"ls\",\"args\":{}}\n").await;
        assert!(line.contains(r#""ok":true"#));
        assert!(line.contains(r#""projects":[]"#));
        assert_eq!(handler.ls_calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn dispatches_cd_with_args() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let line = raw_round_trip(&p, "{\"op\":\"cd\",\"args\":{\"cwd\":\"/x\"}}\n").await;
        assert!(line.contains(r#""ok":true"#));
        assert!(line.contains(r#""outcome":"not_registered""#));
        assert_eq!(handler.cd_calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn handler_err_becomes_wire_error() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        handler.fail_next.store(1, Ordering::SeqCst);
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let line = raw_round_trip(&p, "{\"op\":\"ls\",\"args\":{}}\n").await;
        assert!(line.contains(r#""ok":false"#));
        assert!(line.contains("mock failure"));
    }

    #[tokio::test]
    async fn malformed_request_yields_error_and_keeps_connection() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        let listener = bind_uds(&p).unwrap();
        let handler = Arc::new(MockHandler::new());
        let h = handler.clone();
        tokio::spawn(async move { serve(listener, h).await });

        let mut sock = ClientStream::connect(&p).await.unwrap();
        sock.write_all(b"not json\n").await.unwrap();
        sock.write_all(b"{\"op\":\"ls\",\"args\":{}}\n")
            .await
            .unwrap();
        sock.flush().await.unwrap();
        let mut lines = BufReader::new(sock).lines();
        let l1 = lines.next_line().await.unwrap().unwrap();
        assert!(l1.contains("bad request"));
        let l2 = lines.next_line().await.unwrap().unwrap();
        assert!(l2.contains(r#""ok":true"#));
    }
}
