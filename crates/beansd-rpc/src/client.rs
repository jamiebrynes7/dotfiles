use crate::socket::default_socket_path;
use crate::types::{LsResponse, StartResponse, StatusResponse};
use crate::wire::{WireRequest, WireResponse};
use anyhow::Context;
use serde::de::DeserializeOwned;
use std::io::{BufRead, BufReader, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

pub struct Client {
    socket: PathBuf,
}

impl Client {
    /// Probe the daemon at the default socket path. Returns Err if the
    /// daemon isn't reachable.
    pub fn connect() -> anyhow::Result<Self> {
        let path = default_socket_path()?;
        Self::connect_to(path)
    }

    /// Probe the daemon at a specific socket path.
    pub fn connect_to(socket: PathBuf) -> anyhow::Result<Self> {
        // Open + close a probe stream; surfaces unreachable errors at connect time.
        let _ = UnixStream::connect(&socket)
            .with_context(|| format!("connecting to daemon at {}", socket.display()))?;
        Ok(Self { socket })
    }

    /// Fire-and-forget: write the request, half-close the write side, return.
    /// The daemon writes a response which the kernel discards. Silencing for
    /// non-interactive callers (chpwd hook) is the shell wrapper's job.
    pub fn cd(&self, cwd: PathBuf) -> anyhow::Result<()> {
        let mut sock = UnixStream::connect(&self.socket)
            .with_context(|| format!("connecting to {}", self.socket.display()))?;
        let mut buf = serde_json::to_vec(&WireRequest::Cd { cwd })?;
        buf.push(b'\n');
        sock.write_all(&buf).context("rpc cd: writing request")?;
        sock.shutdown(Shutdown::Write)
            .context("rpc cd: closing write half")?;
        Ok(())
    }

    pub fn ls(&self) -> anyhow::Result<LsResponse> {
        self.send(WireRequest::Ls {}, "ls")
    }

    pub fn start(&self, key: PathBuf) -> anyhow::Result<StartResponse> {
        self.send(WireRequest::Start { key }, "start")
    }

    pub fn stop(&self, key: PathBuf) -> anyhow::Result<()> {
        self.send::<serde_json::Value>(WireRequest::Stop { key }, "stop")
            .map(|_| ())
    }

    pub fn status(&self) -> anyhow::Result<StatusResponse> {
        self.send(WireRequest::Status {}, "status")
    }

    pub fn heartbeat(&self, key: PathBuf) -> anyhow::Result<()> {
        self.send::<serde_json::Value>(WireRequest::Heartbeat { key }, "heartbeat")
            .map(|_| ())
    }

    fn send<T: DeserializeOwned>(&self, req: WireRequest, op: &'static str) -> anyhow::Result<T> {
        let mut sock = UnixStream::connect(&self.socket)
            .with_context(|| format!("rpc {op}: connecting to {}", self.socket.display()))?;
        let mut buf = serde_json::to_vec(&req)?;
        buf.push(b'\n');
        sock.write_all(&buf)
            .with_context(|| format!("rpc {op}: writing request"))?;
        sock.shutdown(Shutdown::Write)
            .with_context(|| format!("rpc {op}: closing write half"))?;

        let mut line = String::new();
        let n = BufReader::new(sock)
            .read_line(&mut line)
            .with_context(|| format!("rpc {op}: reading response"))?;
        if n == 0 {
            anyhow::bail!("rpc {op}: daemon closed connection without responding");
        }
        let resp: WireResponse = serde_json::from_str(&line)
            .with_context(|| format!("rpc {op}: malformed response from daemon"))?;
        match resp {
            WireResponse::Ok { data, .. } => {
                serde_json::from_value(data).with_context(|| format!("rpc {op}: decoding response"))
            }
            WireResponse::Error { error, .. } => {
                Err(anyhow::anyhow!("{error}")).with_context(|| format!("rpc {op}"))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    use tempfile::tempdir;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader as TokioBufReader};
    use tokio::net::UnixListener;
    use tokio::sync::oneshot;

    /// In-process UDS server that, per connection, reads one request line and
    /// writes the supplied response line. Loops so it can serve the probe
    /// connection from `Client::connect_to` and a follow-up request. Awaits a
    /// readiness signal so callers don't need to sleep.
    async fn echo_responder(path: &Path, response: &'static [u8]) {
        let listener = UnixListener::bind(path).unwrap();
        let (ready_tx, ready_rx) = oneshot::channel();
        tokio::spawn(async move {
            let _ = ready_tx.send(());
            while let Ok((sock, _)) = listener.accept().await {
                tokio::spawn(async move {
                    let (rd, mut wr) = sock.into_split();
                    let mut lines = TokioBufReader::new(rd).lines();
                    let _ = lines.next_line().await;
                    let _ = wr.write_all(response).await;
                });
            }
        });
        ready_rx.await.unwrap();
    }

    /// In-process UDS server that consumes one request line per connection and
    /// then drops without writing — the client sees a clean EOF on read.
    /// Reading first matters: dropping before the client finishes writing would
    /// race the kernel buffer and surface as EPIPE instead of EOF.
    async fn silent_responder(path: &Path) {
        let listener = UnixListener::bind(path).unwrap();
        let (ready_tx, ready_rx) = oneshot::channel();
        tokio::spawn(async move {
            let _ = ready_tx.send(());
            while let Ok((sock, _)) = listener.accept().await {
                tokio::spawn(async move {
                    let (rd, _wr) = sock.into_split();
                    let mut lines = TokioBufReader::new(rd).lines();
                    let _ = lines.next_line().await;
                });
            }
        });
        ready_rx.await.unwrap();
    }

    #[tokio::test]
    async fn ls_round_trip() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        echo_responder(&p, b"{\"ok\":true,\"data\":{\"projects\":[]}}\n").await;

        let path = p.clone();
        let resp = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.ls()
        })
        .await
        .unwrap()
        .unwrap();
        assert_eq!(resp.projects.len(), 0);
    }

    #[tokio::test]
    async fn empty_response_maps_to_friendly_error() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        silent_responder(&p).await;

        let path = p.clone();
        let err = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.ls()
        })
        .await
        .unwrap()
        .unwrap_err();
        assert!(err
            .to_string()
            .contains("daemon closed connection without responding"));
    }

    #[tokio::test]
    async fn malformed_response_maps_to_friendly_error() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        echo_responder(&p, b"not json\n").await;

        let path = p.clone();
        let err = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.ls()
        })
        .await
        .unwrap()
        .unwrap_err();
        assert!(format!("{err:#}").contains("malformed response from daemon"));
    }

    #[tokio::test]
    async fn wire_error_propagates_with_op_context() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        echo_responder(&p, b"{\"ok\":false,\"error\":\"unknown project: /x\"}\n").await;

        let path = p.clone();
        let err = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.start(PathBuf::from("/x"))
        })
        .await
        .unwrap()
        .unwrap_err();
        assert!(format!("{err:#}").contains("rpc start"));
        assert!(format!("{err:#}").contains("unknown project"));
    }

    #[tokio::test]
    async fn cd_does_not_read_response() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("sock");
        silent_responder(&p).await;

        let path = p.clone();
        let result = tokio::task::spawn_blocking(move || {
            let c = Client::connect_to(path).unwrap();
            c.cd(PathBuf::from("/some/dir"))
        })
        .await
        .unwrap();
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn connect_to_missing_socket_errors() {
        let result =
            tokio::task::spawn_blocking(|| Client::connect_to(PathBuf::from("/no/such/socket")))
                .await
                .unwrap();
        assert!(result.is_err());
    }
}
