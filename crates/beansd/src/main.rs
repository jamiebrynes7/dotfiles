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

use clap::Parser;

#[derive(Parser)]
#[command(name = "beansd", version)]
struct Cli {
    /// Use the dev instance: dev socket + repo-local dev-config.toml.
    #[arg(long)]
    dev: bool,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(run::run(cli.dev))
}
