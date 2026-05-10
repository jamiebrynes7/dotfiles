mod cli;
mod cli_client;
mod config;
mod control;
mod launcher;
mod logging;
mod port_alloc;
mod project_key;
mod protocol;
mod registry;
mod spawner;
mod supervisor;

use clap::Parser;

fn main() -> anyhow::Result<()> {
    let cli = cli::Cli::parse();
    match cli.command {
        cli::Command::Run => unimplemented!("daemon entrypoint — see F8"),
        cli::Command::Cd { dir } => {
            let socket = control::default_socket_path()?;
            cli_client::send_and_close(&socket, &protocol::Request::Cd { cwd: dir });
            Ok(())
        }
        cli::Command::Ls => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Ls {})?;
            print_response("ls", &resp);
            Ok(())
        }
        cli::Command::Start { key } => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Start { key })?;
            print_response("start", &resp);
            Ok(())
        }
        cli::Command::Stop { key } => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Stop { key })?;
            print_response("stop", &resp);
            Ok(())
        }
        cli::Command::Status => {
            let socket = control::default_socket_path()?;
            let resp = cli_client::request(&socket, &protocol::Request::Status {})?;
            print_response("status", &resp);
            Ok(())
        }
    }
}

fn print_response(label: &str, resp: &protocol::Response) {
    match resp {
        protocol::Response::Ok { data, .. } => {
            println!("{}", serde_json::to_string_pretty(data).unwrap_or_default());
        }
        protocol::Response::Error { error, .. } => {
            eprintln!("beansd {label}: {error}");
            std::process::exit(1);
        }
    }
}
