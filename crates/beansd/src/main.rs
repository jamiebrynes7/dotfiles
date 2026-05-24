mod config;
mod daemon;
mod eviction;
mod health;
mod logging;
mod port_alloc;
mod project_key;
mod registry;
mod run;
mod spawner;
mod supervisor;
mod web;

fn main() -> anyhow::Result<()> {
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(run::run())
}
