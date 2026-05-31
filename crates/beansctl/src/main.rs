use beansd_rpc::Client;
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "beansctl", version)]
struct Cli {
    /// Talk to the dev daemon (matches `beansd --dev`).
    #[arg(long, global = true)]
    dev: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(clap::Subcommand, Debug)]
enum Command {
    /// Register the current beans project (cd-hook target). Fire-and-forget.
    Cd { dir: PathBuf },
    /// List registered projects.
    Ls,
    /// Re-spawn a stopped or evicted project.
    Start { key: PathBuf },
    /// Trigger eviction of a running project.
    Stop { key: PathBuf },
    /// Print daemon status counters.
    Status,
    /// Bump a project's last_used timestamp.
    Heartbeat { key: PathBuf },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let client = if cli.dev {
        Client::connect_to(beansd_rpc::default_socket_path(true)?)?
    } else {
        Client::connect()?
    };
    match cli.command {
        Command::Cd { dir } => client.cd(dir),
        Command::Ls => print_pretty(&client.ls()?),
        Command::Start { key } => print_pretty(&client.start(key)?),
        Command::Stop { key } => client.stop(key),
        Command::Status => print_pretty(&client.status()?),
        Command::Heartbeat { key } => client.heartbeat(key),
    }
}

fn print_pretty<T: serde::Serialize>(value: &T) -> anyhow::Result<()> {
    println!("{}", serde_json::to_string_pretty(value)?);
    Ok(())
}
