---
# dotfiles-qnpn
title: Wire up clap CLI dispatcher with subcommand stubs
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:33:07Z
updated_at: 2026-05-09T13:32:42Z
parent: dotfiles-m592
blocked_by:
    - dotfiles-uzwl
---

**Files:**
- Create: `packages/beans-daemon/src/cli.rs`
- Modify: `packages/beans-daemon/src/main.rs`
- Test: inline `#[cfg(test)] mod tests` in `cli.rs`

- [x] **Step 1: Write the failing test**

Append to `packages/beans-daemon/src/cli.rs`:
```rust
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd packages/beans-daemon && cargo test --no-run 2>&1`
Expected: FAIL — `src/cli.rs` not declared as a module yet, so `mod cli` is missing.

- [x] **Step 3: Wire `cli` module into main.rs and dispatch**

Replace `packages/beans-daemon/src/main.rs` with:
```rust
mod cli;

use clap::Parser;

fn main() -> anyhow::Result<()> {
    let cli = cli::Cli::parse();
    match cli.command {
        cli::Command::Run     => unimplemented!("daemon entrypoint — see F8"),
        cli::Command::Cd { .. }     => unimplemented!("cd client — see F7"),
        cli::Command::Ls            => unimplemented!("ls client — see F7"),
        cli::Command::Start { .. }  => unimplemented!("start client — see F7"),
        cli::Command::Stop { .. }   => unimplemented!("stop client — see F7"),
        cli::Command::Status        => unimplemented!("status client — see F7"),
    }
}
```

- [x] **Step 4: Run tests**

Run: `cargo test`
Expected: 2 tests pass (`cli_definition_is_valid`, `parses_cd_subcommand`).

- [x] **Step 5: Verify --help and --version still work**

Run: `cargo run -- --help`
Expected: usage text listing all 6 subcommands.

Run: `cargo run -- --version`
Expected: `beansd 0.1.0`

- [x] **Step 6: Commit**

```bash
git add packages/beans-daemon/src/cli.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: clap CLI dispatcher with subcommand stubs"
```

## Summary of Changes

- Created `packages/beans-daemon/src/cli.rs` with a `Cli` parser and `Command` enum covering the six daemon subcommands: `run`, `cd`, `ls`, `start`, `stop`, `status`.
- Added inline tests: `cli_definition_is_valid` (debug_assert via `CommandFactory`) and `parses_cd_subcommand`.
- Replaced `packages/beans-daemon/src/main.rs` placeholder with a clap `parse()` + match dispatcher that routes each subcommand to an `unimplemented!` stub referencing the future feature it belongs to (F7 / F8).
- Verified `cargo test` passes (2/2) and `--help` / `--version` render correctly (`beansd 0.1.0`).
