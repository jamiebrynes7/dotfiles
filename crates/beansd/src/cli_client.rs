use crate::protocol::{Request, Response};
use anyhow::Context;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;

pub fn request(socket: &Path, req: &Request) -> anyhow::Result<Response> {
    let mut sock = UnixStream::connect(socket)
        .with_context(|| format!("connecting {}", socket.display()))?;
    let mut buf = serde_json::to_vec(req)?;
    buf.push(b'\n');
    sock.write_all(&buf)?;
    sock.shutdown(std::net::Shutdown::Write)?;
    let mut line = String::new();
    BufReader::new(sock).read_line(&mut line)?;
    Ok(serde_json::from_str(&line)?)
}

/// Fire-and-forget send. Used by `cd`. Silent on connection errors so the
/// shell prompt is never disturbed when the daemon isn't running.
pub fn send_and_close(socket: &Path, req: &Request) {
    let Ok(mut sock) = UnixStream::connect(socket) else {
        return;
    };
    let Ok(mut buf) = serde_json::to_vec(req) else {
        return;
    };
    buf.push(b'\n');
    let _ = sock.write_all(&buf);
    let _ = sock.shutdown(std::net::Shutdown::Both);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use tempfile::tempdir;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader as TokioBufReader};
    use tokio::net::UnixListener;

    /// Stand up a tiny in-process UDS server that echoes one line back per
    /// connection, so we can verify the client framing without involving the
    /// real `Daemon`. The server is dropped when the test returns.
    async fn echo_server(path: PathBuf, response: Vec<u8>) {
        let listener = UnixListener::bind(&path).unwrap();
        tokio::spawn(async move {
            if let Ok((sock, _)) = listener.accept().await {
                let (rd, mut wr) = sock.into_split();
                let mut lines = TokioBufReader::new(rd).lines();
                let _ = lines.next_line().await;
                let _ = wr.write_all(&response).await;
            }
        });
    }

    #[tokio::test]
    async fn request_round_trip() {
        let dir = tempdir().unwrap();
        let sock_path = dir.path().join("sock");
        echo_server(sock_path.clone(), b"{\"ok\":true,\"data\":{\"x\":1}}\n".to_vec()).await;
        // Give the listener a moment to start accepting.
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;

        let path = sock_path.clone();
        let resp = tokio::task::spawn_blocking(move || request(&path, &Request::Ls {}))
            .await
            .unwrap()
            .unwrap();
        match resp {
            Response::Ok { data, .. } => assert_eq!(data["x"], 1),
            other => panic!("expected ok, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn send_and_close_silent_when_socket_missing() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("nope");
        // Should not panic or block.
        tokio::task::spawn_blocking(move || {
            send_and_close(&path, &Request::Cd { cwd: "/x".into() })
        })
        .await
        .unwrap();
    }
}
