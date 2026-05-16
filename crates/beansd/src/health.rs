use async_trait::async_trait;
use std::time::{Duration, Instant};

/// Poll a freshly-spawned child until it responds healthy or `timeout` elapses.
/// Production uses HTTP; tests inject a mock to avoid binding real ports.
#[async_trait]
pub trait HealthChecker: Send + Sync + 'static {
    async fn wait_until_healthy(&self, port: u16, timeout: Duration) -> bool;
}

pub struct HttpHealthChecker;

#[async_trait]
impl HealthChecker for HttpHealthChecker {
    async fn wait_until_healthy(&self, port: u16, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;
        let url = format!("http://127.0.0.1:{port}/");
        loop {
            if Instant::now() >= deadline {
                return false;
            }
            if let Ok(resp) = reqwest::get(&url).await {
                if resp.status().is_success() {
                    return true;
                }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Mock checker for tests. Configurable: always ready, never ready,
    /// or fail the first N calls before reporting ready.
    pub(crate) struct MockHealthChecker {
        calls: AtomicUsize,
        fail_first_n: usize,
        never_ready: bool,
    }

    impl MockHealthChecker {
        pub(crate) fn always_ready() -> Self {
            Self {
                calls: AtomicUsize::new(0),
                fail_first_n: 0,
                never_ready: false,
            }
        }

        pub(crate) fn never_ready() -> Self {
            Self {
                calls: AtomicUsize::new(0),
                fail_first_n: 0,
                never_ready: true,
            }
        }

        pub(crate) fn fail_first(n: usize) -> Self {
            Self {
                calls: AtomicUsize::new(0),
                fail_first_n: n,
                never_ready: false,
            }
        }
    }

    #[async_trait]
    impl HealthChecker for MockHealthChecker {
        async fn wait_until_healthy(&self, _port: u16, _timeout: Duration) -> bool {
            if self.never_ready {
                return false;
            }
            let n = self.calls.fetch_add(1, Ordering::SeqCst);
            n >= self.fail_first_n
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn http_checker_polls_until_ready() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        tokio::spawn(async move {
            use axum::routing::get;
            let app = axum::Router::new().route("/", get(|| async { "ok" }));
            axum::serve(listener, app).await.ok();
        });

        let ok = HttpHealthChecker
            .wait_until_healthy(port, Duration::from_secs(2))
            .await;
        assert!(ok);
    }

    #[tokio::test]
    async fn http_checker_times_out_when_unreachable() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);

        let ok = HttpHealthChecker
            .wait_until_healthy(port, Duration::from_millis(150))
            .await;
        assert!(!ok);
    }
}
