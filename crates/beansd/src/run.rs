use crate::config::Config;
use crate::daemon::Daemon;
use crate::health::HttpHealthChecker;
use crate::launcher::{router_with_state, LauncherState};
use crate::registry::Registry;
use crate::spawner::BeansServeSpawner;
use crate::supervisor::Supervisor;
use beansd_rpc::{bind_uds, default_socket_path};
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
        health_checker: HttpHealthChecker,
        health_attempts: 10,
        health_interval: Duration::from_secs(1),
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
        tokio::spawn(async move { beansd_rpc::serve(uds_listener, d).await })
    };

    let launcher_addr = std::net::SocketAddr::from(([127, 0, 0, 1], cfg.launcher_port));
    let tcp = tokio::net::TcpListener::bind(launcher_addr).await?;
    let app = router_with_state(LauncherState {
        registry: registry.clone(),
        daemon: daemon.clone(),
    });
    tracing::info!(%launcher_addr, "HTTP launcher bound");
    let http_task = tokio::spawn(async move { axum::serve(tcp, app).await });

    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut sigint = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
    tokio::select! {
        _ = sigterm.recv() => { tracing::info!("SIGTERM received; shutting down"); }
        _ = sigint.recv()  => { tracing::info!("SIGINT received; shutting down"); }
        r = uds_task       => { tracing::error!(?r, "UDS server exited unexpectedly"); }
        r = http_task      => { tracing::error!(?r, "HTTP server exited unexpectedly"); }
    }

    // Best-effort SIGTERM to all healthy children. Service manager will reap
    // us; each child's own shutdown handler does the rest.
    let reg = registry.lock().await;
    for p in reg.iter() {
        if let crate::registry::ProjectState::Healthy { pid, .. } = &p.state {
            let _ = nix::sys::signal::kill(
                nix::unistd::Pid::from_raw(*pid as i32),
                nix::sys::signal::Signal::SIGTERM,
            );
        }
    }
    drop(reg);
    Ok(())
}
