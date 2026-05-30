---
# dotfiles-uc8x
title: Add the which crate to the workspace
status: todo
type: task
created_at: 2026-05-30T18:32:16Z
updated_at: 2026-05-30T18:32:16Z
parent: dotfiles-i5zy
---

Add the `which` crate (used to resolve `beans-serve` on `$PATH`) to the workspace dependency set and inherit it in `beansd`. No code uses it yet — this is dependency plumbing so the next task compiles.

**Files:**
- Modify: `Cargo.toml` (root, `[workspace.dependencies]`)
- Modify: `crates/beansd/Cargo.toml` (`[dependencies]`)

- [ ] **Step 1: Add `which` to `[workspace.dependencies]`**

In the root `Cargo.toml`, under `[workspace.dependencies]`, add (keep the list tidy):

```toml
which = "7"
```

- [ ] **Step 2: Inherit it in beansd**

In `crates/beansd/Cargo.toml`, under `[dependencies]`, add:

```toml
which.workspace = true
```

- [ ] **Step 3: Verify it resolves and builds**

Run: `cargo build -p beansd`
Expected: success; `Cargo.lock` updated to include `which`.

- [ ] **Step 4: Commit**

```bash
git add Cargo.toml crates/beansd/Cargo.toml Cargo.lock
git commit -m "crates beansd: add which dependency for \$PATH lookup (dotfiles-z3aj)"
```
