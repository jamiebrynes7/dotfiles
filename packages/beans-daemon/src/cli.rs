use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "beansd", version)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(clap::Subcommand, Debug)]
pub enum Command {
    /// Run the daemon (entrypoint for launchd/systemd-user).
    Run,
    /// Register the current beans project (cd-hook target).
    Cd { dir: std::path::PathBuf },
    /// List registered projects.
    Ls,
    /// Spawn a stopped project's beans-serve.
    Start { key: std::path::PathBuf },
    /// Stop a running project's beans-serve.
    Stop { key: std::path::PathBuf },
    /// Print daemon health.
    Status,
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn cli_definition_is_valid() {
        Cli::command().debug_assert();
    }

    #[test]
    fn parses_cd_subcommand() {
        let cli = Cli::try_parse_from(["beansd", "cd", "/tmp/foo"]).unwrap();
        assert!(matches!(cli.command, Command::Cd { dir } if dir == std::path::PathBuf::from("/tmp/foo")));
    }
}
