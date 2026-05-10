use crate::config::Config;
use crate::control::{Daemon, bind_uds, default_socket_path};
use crate::launcher::{LauncherState, router_with_state};
use crate::registry::Registry;
use crate::spawner::BeansServeSpawner;
use crate::supervisor::Supervisor;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub async fn run() -> anyhow::Result<()> {
    let cfg = Config::load(&Config::default_path()?)?;
    cfg.validate()?;

    crate::logging::init(&cfg.log_level)?;
    tracing::info!(version = env!("CARGO_PKG_VERSION"), "beansd starting");
    tracing::info!(
        ?cfg.beans_serve_path,
        port = cfg.launcher_port,
        lru_cap = cfg.lru_cap,
        "loaded config"
    );

    let registry = Arc::new(Mutex::new(Registry::new()));
    let supervisor = Arc::new(Supervisor {
        registry: registry.clone(),
        spawner: BeansServeSpawner {
            binary: cfg.beans_serve_path.clone(),
        },
        health_timeout: Duration::from_secs(5),
        children: Arc::new(Mutex::new(HashMap::new())),
    });
    let daemon = Arc::new(Daemon {
        registry: registry.clone(),
        supervisor: supervisor.clone(),
        lru_cap: cfg.lru_cap,
        sigterm_grace: Duration::from_secs(5),
        sigkill_grace: Duration::from_secs(5),
        start_max_attempts: 3,
        start_base_backoff: Duration::from_secs(1),
    });

    let uds_path = default_socket_path()?;
    let uds_listener = bind_uds(&uds_path)?;
    tracing::info!(path = %uds_path.display(), "UDS bound");
    let uds_task = {
        let d = daemon.clone();
        tokio::spawn(async move { d.serve_uds(uds_listener).await })
    };

    let launcher_addr = std::net::SocketAddr::from(([127, 0, 0, 1], cfg.launcher_port));
    let tcp = tokio::net::TcpListener::bind(launcher_addr).await?;
    let app = router_with_state(LauncherState {
        registry: registry.clone(),
        daemon: daemon.clone(),
    });
    tracing::info!(%launcher_addr, "HTTP launcher bound");
    let http_task = tokio::spawn(async move { axum::serve(tcp, app).await });

    tokio::select! {
        r = uds_task  => { tracing::error!(?r, "UDS server exited"); }
        r = http_task => { tracing::error!(?r, "HTTP server exited"); }
    }
    Ok(())
}
