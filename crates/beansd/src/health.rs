use async_trait::async_trait;
use std::time::Duration;

/// Poll a freshly-spawned child until it responds healthy or attempts are exhausted.
/// Production uses HTTP; tests inject a mock to avoid binding real ports.
#[async_trait]
pub trait HealthChecker: Send + Sync + 'static {
    async fn wait_until_healthy(&self, port: u16, attempts: u32, interval: Duration) -> bool;
}

pub struct HttpHealthChecker;

#[async_trait]
impl HealthChecker for HttpHealthChecker {
    async fn wait_until_healthy(&self, port: u16, attempts: u32, interval: Duration) -> bool {
        let url = format!("http://127.0.0.1:{port}/");
        for _ in 0..attempts {
            let response = match tokio::time::timeout(interval, reqwest::get(&url)).await {
                Ok(resp) => resp,
                Err(_) => continue,
            };

            if let Ok(resp) = response {
                if resp.status().is_success() {
                    return true;
                }
            }

            tokio::time::sleep(interval).await;
        }
        false
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
        async fn wait_until_healthy(
            &self,
            _port: u16,
            _attempts: u32,
            _interval: Duration,
        ) -> bool {
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
            .wait_until_healthy(port, 5, Duration::from_millis(500))
            .await;
        assert!(ok);
    }

    #[tokio::test]
    async fn http_checker_times_out_when_unreachable() {
        // Port 1 is almost certainly not running an HTTP server.
        let ok = HttpHealthChecker
            .wait_until_healthy(1, 3, Duration::from_millis(50))
            .await;
        assert!(!ok);
    }

    #[tokio::test]
    async fn http_checker_times_out_when_unresponsive() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        tokio::spawn(async move {
            use axum::routing::get;
            let app = axum::Router::new().route(
                "/",
                get(|| async {
                    tokio::time::sleep(Duration::from_secs(60)).await;
                    "ok"
                }),
            );
            axum::serve(listener, app).await.ok();
        });

        let ok = HttpHealthChecker
            .wait_until_healthy(port, 3, Duration::from_millis(50))
            .await;
        assert!(!ok);
    }
}
