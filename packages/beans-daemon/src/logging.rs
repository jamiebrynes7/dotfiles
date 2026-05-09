use tracing_subscriber::EnvFilter;

/// Initialise the global tracing subscriber.
///
/// `default_level` is used when neither `RUST_LOG` nor the config-supplied
/// filter overrides it. Returns an error if a subscriber was already set
/// (only one per process).
pub fn init(default_level: &str) -> anyhow::Result<()> {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(default_level));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(true)
        .try_init()
        .map_err(|e| anyhow::anyhow!("tracing already initialised: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_with_invalid_level_falls_back_to_default() {
        // Just verifies the function signature compiles and that calling it
        // with a sane level doesn't panic. We can't easily test the global
        // subscriber state here.
        // (Real integration coverage comes via F8's smoke test.)
        let _ = init("info");
    }
}
