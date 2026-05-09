mod cli;
mod logging;

use clap::Parser;

fn main() -> anyhow::Result<()> {
    let cli = cli::Cli::parse();
    match cli.command {
        cli::Command::Run => unimplemented!("daemon entrypoint — see F8"),
        cli::Command::Cd { .. } => unimplemented!("cd client — see F7"),
        cli::Command::Ls => unimplemented!("ls client — see F7"),
        cli::Command::Start { .. } => unimplemented!("start client — see F7"),
        cli::Command::Stop { .. } => unimplemented!("stop client — see F7"),
        cli::Command::Status => unimplemented!("status client — see F7"),
    }
}
