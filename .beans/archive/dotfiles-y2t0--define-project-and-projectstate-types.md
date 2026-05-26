---
# dotfiles-y2t0
title: Define `Project` and `ProjectState` types
status: completed
type: task
priority: normal
created_at: 2026-05-03T14:34:36Z
updated_at: 2026-05-09T13:48:54Z
parent: dotfiles-yejq
---

**Files:**
- Create: `packages/beans-daemon/src/registry.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod registry;`)

Per spec §3 — type-driven design: fields that only exist for live children (`port`, `pid`, `spawned_at`) live inside the `Healthy` variant.

- [x] **Step 1: Write the failing test**

Create `packages/beans-daemon/src/registry.rs`:
```rust
use std::path::PathBuf;
use std::time::Instant;

#[derive(Debug)]
pub struct Project {
    pub key:          PathBuf,
    pub display_name: String,
    pub last_used:    Instant,
    pub state:        ProjectState,
}

#[derive(Debug)]
pub enum ProjectState {
    Spawning { since: Instant },
    Healthy  { port: u16, pid: u32, spawned_at: Instant },
    Evicting { since: Instant },
    Dead     { reason: String, since: Instant },
}

impl ProjectState {
    /// True when the project counts toward the LRU cap.
    /// Evicting and Dead projects don't.
    pub fn counts_toward_cap(&self) -> bool {
        matches!(self, ProjectState::Spawning { .. } | ProjectState::Healthy { .. })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_toward_cap_for_active_states() {
        let now = Instant::now();
        assert!( ProjectState::Spawning { since: now }.counts_toward_cap());
        assert!( ProjectState::Healthy  { port: 1, pid: 2, spawned_at: now }.counts_toward_cap());
        assert!(!ProjectState::Evicting { since: now }.counts_toward_cap());
        assert!(!ProjectState::Dead     { reason: "x".into(), since: now }.counts_toward_cap());
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cargo test registry::`
Expected: FAIL — `mod registry` not declared.

- [x] **Step 3: Wire into main.rs**

Add `mod registry;` to `packages/beans-daemon/src/main.rs`.

- [x] **Step 4: Run tests**

Run: `cargo test registry::`
Expected: 1 test passes.

- [x] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/registry.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: Project + ProjectState types"
```

## Summary of Changes

- Created `packages/beans-daemon/src/registry.rs` with `Project { key, display_name, last_used, state }` and a `ProjectState` enum (`Spawning`, `Healthy`, `Evicting`, `Dead`). Live-only fields (`port`, `pid`, `spawned_at`) are scoped inside `Healthy` per spec §3.
- Added `ProjectState::counts_toward_cap()` returning `true` only for `Spawning` and `Healthy` — used by the upcoming LRU cap accounting.
- Wired `mod registry;` into `main.rs`. One test under `cargo test registry::` covers the four state arms.
