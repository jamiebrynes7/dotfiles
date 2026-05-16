use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "beansd", version)]
pub struct Cli {}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn cli_definition_is_valid() {
        Cli::command().debug_assert();
    }
}
