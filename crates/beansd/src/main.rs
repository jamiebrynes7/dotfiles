mod cli;
mod config;
mod daemon;
mod handler;
mod launcher;
mod logging;
mod port_alloc;
mod project_key;
mod registry;
mod run;
mod spawner;
mod supervisor;

use clap::Parser;

fn main() -> anyhow::Result<()> {
    let _ = cli::Cli::parse();
    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(run::run())
}
