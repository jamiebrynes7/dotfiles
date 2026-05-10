mod cli;
mod cli_client;
mod config;
mod control;
mod launcher;
mod logging;
mod port_alloc;
mod project_key;
mod registry;
mod run;
mod spawner;
mod supervisor;

use beansd_rpc::{WireRequest, WireResponse, default_socket_path};
use clap::Parser;

fn main() -> anyhow::Result<()> {
    let cli = cli::Cli::parse();
    match cli.command {
        cli::Command::Run => {
            let rt = tokio::runtime::Runtime::new()?;
            rt.block_on(run::run())
        }
        cli::Command::Cd { dir } => {
            let socket = default_socket_path()?;
            cli_client::send_and_close(&socket, &WireRequest::Cd { cwd: dir });
            Ok(())
        }
        cli::Command::Ls => {
            let socket = default_socket_path()?;
            let resp = cli_client::request(&socket, &WireRequest::Ls {})?;
            print_response("ls", &resp);
            Ok(())
        }
        cli::Command::Start { key } => {
            let socket = default_socket_path()?;
            let resp = cli_client::request(&socket, &WireRequest::Start { key })?;
            print_response("start", &resp);
            Ok(())
        }
        cli::Command::Stop { key } => {
            let socket = default_socket_path()?;
            let resp = cli_client::request(&socket, &WireRequest::Stop { key })?;
            print_response("stop", &resp);
            Ok(())
        }
        cli::Command::Status => {
            let socket = default_socket_path()?;
            let resp = cli_client::request(&socket, &WireRequest::Status {})?;
            print_response("status", &resp);
            Ok(())
        }
    }
}

fn print_response(label: &str, resp: &WireResponse) {
    match resp {
        WireResponse::Ok { data, .. } => {
            println!("{}", serde_json::to_string_pretty(data).unwrap_or_default());
        }
        WireResponse::Error { error, .. } => {
            eprintln!("beansd {label}: {error}");
            std::process::exit(1);
        }
    }
}
