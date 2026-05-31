use crate::config::Config;
use crate::daemon::Daemon;
use crate::eviction::{Evictor, EvictorConfig};
use crate::health::HttpHealthChecker;
use crate::registry::Registry;
use crate::spawner::BeansServeSpawner;
use crate::web;
use beansd_rpc::{bind_uds, default_socket_path};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub async fn run(dev: bool) -> anyhow::Result<()> {
    let cfg = Config::load(&Config::default_path(dev)?)?;
    cfg.validate()?;
    let beans_serve = cfg.resolve_beans_serve()?;

    crate::logging::init(&cfg.log_level)?;
    tracing::info!(version = env!("CARGO_PKG_VERSION"), "beansd starting");
    tracing::info!(
        ?beans_serve,
        port = cfg.launcher_port,
        lru_cap = cfg.lru_cap,
        "loaded config"
    );

    let registry = Arc::new(Mutex::new(Registry::new()));
    let spawner = BeansServeSpawner {
        binary: beans_serve,
    };
    let supervisor = crate::supervisor::new(registry.clone(), spawner, HttpHealthChecker);
    let daemon = Arc::new(Daemon {
        registry: registry.clone(),
        supervisor: supervisor.clone(),
        lru_cap: cfg.lru_cap,
    });

    let uds_path = default_socket_path(dev)?;
    let uds_listener = bind_uds(&uds_path)?;
    tracing::info!(path = %uds_path.display(), "UDS bound");
    let uds_task = {
        let d = daemon.clone();
        tokio::spawn(async move { beansd_rpc::serve(uds_listener, d).await })
    };

    let server = web::Server::bind(registry.clone(), daemon.clone(), cfg.launcher_port).await?;
    tracing::info!(addr = %server.local_addr(), "HTTP launcher bound");
    let http_task = tokio::spawn(server.serve());

    let eviction_task = Evictor::new(
        registry.clone(),
        supervisor.clone(),
        EvictorConfig {
            lru_cap: cfg.lru_cap,
            poll_interval: Duration::from_secs(60),
        },
    )
    .spawn();

    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut sigint = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
    tokio::select! {
        _ = sigterm.recv() => { tracing::info!("SIGTERM received; shutting down"); }
        _ = sigint.recv()  => { tracing::info!("SIGINT received; shutting down"); }
        r = uds_task       => { tracing::error!(?r, "UDS server exited unexpectedly"); }
        r = http_task      => { tracing::error!(?r, "HTTP server exited unexpectedly"); }
        r = eviction_task  => { tracing::error!(?r, "Eviction task exited unexpectedly"); }
    }

    // Best-effort SIGTERM to all healthy children. Service manager will reap
    // us; each child's own shutdown handler does the rest.
    let reg = registry.lock().await;
    for p in reg.iter() {
        if let crate::registry::ProjectState::Healthy { child, .. } = &p.state {
            let _ = nix::sys::signal::kill(
                nix::unistd::Pid::from_raw(child.pid() as i32),
                nix::sys::signal::Signal::SIGTERM,
            );
        }
    }
    drop(reg);
    Ok(())
}
