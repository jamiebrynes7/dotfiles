---
# dotfiles-uzwl
title: Initialize `packages/beans-daemon` crate
status: todo
type: task
priority: normal
created_at: 2026-05-03T14:33:07Z
updated_at: 2026-05-03T14:55:43Z
parent: dotfiles-m592
blocked_by:
    - dotfiles-g2br
---

**Files:**
- Create: `packages/beans-daemon/Cargo.toml`
- Create: `packages/beans-daemon/src/main.rs`
- Create: `packages/beans-daemon/.gitignore` (just `target/`)

- [ ] **Step 1: Create the crate skeleton**

`packages/beans-daemon/Cargo.toml`:
```toml
[package]
name = "beans-daemon"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "beansd"
path = "src/main.rs"

[dependencies]
anyhow = "1"
askama = "0.12"
axum = { version = "0.7", features = ["macros"] }
clap = { version = "4", features = ["derive"] }
nix = { version = "0.29", features = ["signal"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
tokio = { version = "1", features = ["full"] }
tokio-util = { version = "0.7", features = ["codec"] }
toml = "0.8"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

[dev-dependencies]
assert_matches = "1"
tempfile = "3"
```

`packages/beans-daemon/src/main.rs`:
```rust
fn main() {
    println!("beansd 0.1.0");
}
```

`packages/beans-daemon/.gitignore`:
```
target/
```

- [ ] **Step 2: Build the crate**

Run: `cd packages/beans-daemon && cargo build`
Expected: compiles cleanly, produces `target/debug/beansd`. Cargo will create `Cargo.lock`.

- [ ] **Step 3: Run the binary**

Run: `./target/debug/beansd`
Expected output: `beansd 0.1.0`

- [ ] **Step 4: Commit**

```bash
git add packages/beans-daemon/Cargo.toml packages/beans-daemon/Cargo.lock packages/beans-daemon/src/main.rs packages/beans-daemon/.gitignore
git commit -m "packages/beans-daemon: initial crate scaffold"
```
