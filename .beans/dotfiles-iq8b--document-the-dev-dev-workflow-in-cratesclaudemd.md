---
# dotfiles-iq8b
title: Document the --dev dev workflow in crates/CLAUDE.md
status: todo
type: task
priority: normal
created_at: 2026-05-30T18:33:34Z
updated_at: 2026-05-30T18:33:46Z
parent: dotfiles-spyq
blocked_by:
    - dotfiles-paxh
    - dotfiles-o1zs
---

Document how to run a dev daemon alongside prod, so the workflow is discoverable. Keep it short and concrete.

**Files:**
- Modify: `crates/CLAUDE.md` (add a subsection; bump the Freshness date to 2026-05-30)

- [ ] **Step 1: Add a "Dev instance (`--dev`)" subsection**

Under the `## Commands` section of `crates/CLAUDE.md`, add:

```markdown
### Dev instance (`--dev`)

To run a dev `beansd` alongside the launchd-managed prod daemon on the same
machine, pass `--dev` to both binaries. It selects a separate socket
(`…/sock-dev`) and the repo-local `crates/beansd/dev-config.toml` (launcher port
9001, `beans_serve_path` resolved from `$PATH`). Prod and the chpwd/prime hooks
never pass `--dev`, so they're untouched.

    cargo run -p beansd  -- --dev          # dev daemon (sock-dev, port 9001)
    cargo run -p beansctl -- --dev status  # dev CLI -> dev daemon

`beans-serve` must be on `$PATH` (it is, via the home-manager `beans` package).
```

- [ ] **Step 2: Bump the Freshness date**

At the top of `crates/CLAUDE.md`, change the `Freshness:` line to `Freshness: 2026-05-30`.

- [ ] **Step 3: Commit**

```bash
git add crates/CLAUDE.md
git commit -m "crates: document the --dev dev workflow (dotfiles-z3aj)"
```
