---
# dotfiles-hjfu
title: Rewrite app.css for top-bar layout and smoke-test
status: completed
type: task
priority: normal
created_at: 2026-05-26T20:22:21Z
updated_at: 2026-05-31T20:04:41Z
parent: dotfiles-a93p
---

**Files:**
- Modify: `crates/beansd/src/web/static/app.css` (full rewrite)

**Depends on:** Task `dotfiles-x9za` (uses class names `.project-switcher`, `.project-row`, `.topbar-detail`, `#topbar`, `.caret`, `.panel`, etc.)

- [x] **Step 1: Replace `app.css` contents**

Overwrite `crates/beansd/src/web/static/app.css` with:

```css
* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  height: 100vh;
  display: grid;
  grid-template-rows: 40px 1fr;
}

#topbar {
  background: #1e1e2e;
  color: #cdd6f4;
  padding: 0 1rem;
  display: flex;
  align-items: center;
  gap: 1rem;
}

details.project-switcher { position: relative; }
details.project-switcher > summary {
  list-style: none;
  padding: 0.35rem 0.6rem;
  border-radius: 4px;
  cursor: pointer;
}
details.project-switcher > summary::-webkit-details-marker { display: none; }
details.project-switcher > summary:hover { background: #313244; }

.caret { opacity: 0.6; margin-left: 0.3rem; }

details[open] > .panel {
  position: absolute;
  top: 100%;
  left: 0;
  min-width: 280px;
  max-width: 480px;
  background: #1e1e2e;
  border: 1px solid #313244;
  border-radius: 4px;
  z-index: 10;
  max-height: 60vh;
  overflow-y: auto;
  margin-top: 0.25rem;
}

.project-row {
  display: grid;
  grid-template-columns: 1fr auto;
  column-gap: 0.75rem;
  padding: 0.5rem 0.75rem;
  color: inherit;
  text-decoration: none;
}
.project-row .name { grid-column: 1; grid-row: 1; font-weight: 500; }
.project-row .path {
  grid-column: 1;
  grid-row: 2;
  font-family: ui-monospace, monospace;
  font-size: 0.7rem;
  opacity: 0.6;
}
.project-row .badge { grid-column: 2; grid-row: 1 / 3; align-self: center; }
.project-row:hover { background: #313244; }
.project-row.active { background: #45475a; }

.topbar-detail {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-left: auto;
  min-width: 0;
}
.topbar-detail .path {
  font-family: ui-monospace, monospace;
  font-size: 0.8rem;
  opacity: 0.7;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.topbar-detail .port {
  font-family: ui-monospace, monospace;
  font-size: 0.8rem;
  opacity: 0.7;
}

.badge {
  display: inline-block;
  font-size: 0.65rem;
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
}
.badge.healthy  { background: #a6e3a1; color: #1e1e2e; }
.badge.spawning { background: #f9e2af; color: #1e1e2e; }
.badge.evicting { background: #fab387; color: #1e1e2e; }
.badge.dead     { background: #f38ba8; color: #1e1e2e; }

main { display: flex; flex-direction: column; }
main iframe { flex: 1; border: none; width: 100%; }
main .empty {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  opacity: 0.5;
}
```

- [x] **Step 2: Run `nix flake check`**

Run: `nix flake check`
Expected: PASS (CSS is a static asset — confirms the workspace still builds and all tests still pass under Nix).

- [x] **Step 3: Smoke test against a running daemon** (verified manually — all 5 acceptance checks pass)

In one shell:

```bash
cargo run -p beansd
```

In a browser, walk through the acceptance criteria from the spec:

1. Visit `http://127.0.0.1:<wrapper-port>/` with no `?project=` — confirm a top bar is visible with summary text "Select a project ▾", no right-hand detail strip, main area shows "No active project."
2. Register a project (via `beansctl` or by `cd`ing into a directory that triggers registration). Within 5 seconds the dropdown row count should increase without reloading.
3. Click the row — page navigates to `/?project=<key>`. Summary text becomes the project's display name, right-hand detail strip shows a healthy badge + path (mono, truncated if narrow) + `:port`, iframe loads the project's `beans-serve`.
4. Open the dropdown — confirm each row shows name (top), path (mono, smaller, dimmed), status badge on the right; the active row is highlighted.
5. Stop the project's child via the daemon and wait ≤5s — the badge in the dropdown and the detail strip should flip to `dead` (or `evicting`, then `dead`).

- [x] **Step 4: Commit**

```bash
git add crates/beansd/src/web/static/app.css
git commit -m "style(beansd): rewrite wrapper CSS for top-bar layout"
```
