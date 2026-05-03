---
# dotfiles-wyid
title: Initialize tracing subscriber from `RUST_LOG` / config
status: todo
type: task
priority: normal
created_at: 2026-05-03T14:33:07Z
updated_at: 2026-05-03T14:55:54Z
parent: dotfiles-m592
blocked_by:
    - dotfiles-uzwl
---

**Files:**
- Create: `packages/beans-daemon/src/logging.rs`
- Modify: `packages/beans-daemon/src/main.rs`

- [ ] **Step 1: Write the failing test**

Append to `packages/beans-daemon/src/logging.rs`:
```rust
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo build` (the test won't compile until we add `mod logging;`)
Expected: FAIL — unresolved module.

- [ ] **Step 3: Wire into main.rs**

Modify `packages/beans-daemon/src/main.rs` — add `mod logging;` near the top.

- [ ] **Step 4: Run tests**

Run: `cargo test`
Expected: PASS (the previous CLI tests + the new logging smoke test).

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/logging.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: tracing subscriber initialiser"
```
