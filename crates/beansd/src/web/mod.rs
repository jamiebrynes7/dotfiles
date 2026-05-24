use crate::daemon::Daemon;
use crate::registry::Registry;
use axum::Router;
use std::future::Future;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::Mutex;

mod routes;
mod views;

#[cfg(test)]
mod test_utils;

#[derive(Clone)]
pub(in crate::web) struct State {
    pub(in crate::web) registry: Arc<Mutex<Registry>>,
    pub(in crate::web) daemon: Arc<Daemon>,
}

fn router(state: State) -> Router {
    routes::router().with_state(state)
}

pub struct Server {
    listener: TcpListener,
    router: Router,
}

impl Server {
    pub async fn bind(
        registry: Arc<Mutex<Registry>>,
        daemon: Arc<Daemon>,
        port: u16,
    ) -> anyhow::Result<Self> {
        let state = State { registry, daemon };
        let router = router(state);
        let addr = SocketAddr::from(([127, 0, 0, 1], port));
        let listener = TcpListener::bind(addr).await?;
        Ok(Self { listener, router })
    }

    pub fn local_addr(&self) -> SocketAddr {
        self.listener
            .local_addr()
            .expect("bound listener has a local address")
    }

    pub fn serve(self) -> impl Future<Output = std::io::Result<()>> + Send + 'static {
        async move { axum::serve(self.listener, self.router).await }
    }
}
