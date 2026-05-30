# beans daemon wrapper UI: top-bar redesign

Bean: `dotfiles-a93p` — "[beans daemon] tweak wrapper UI"

## Goal

Replace the 280px left sidebar in the beans daemon launcher (`crates/beansd/src/web/`) with a thin top bar containing:

- A custom rich dropdown for switching the active project. Each row shows project name, filesystem path (mono, small), and a status badge.
- An always-visible detail strip for the active project: status badge, path, port. (Project name is in the dropdown's `<summary>` and is not repeated.)

The iframe takes the rest of the viewport.

## Non-goals

- No keyboard arrow-nav between dropdown options (defer; native `<details>` tab order is acceptable).
- No click-outside-to-close behavior (defer; clicking the summary again toggles).
- No animation / transitions.
- No new project-management actions in the bar (start/stop/evict remain out of scope).

## Layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [ dotfiles ▾ ]                  ●healthy   ~/workspace/.../dotfiles  :4242   │  ← #topbar, ~40px
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                          <iframe src="http://127.0.0.1:PORT/">               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

When no project is active:

- Summary text is `Select a project ▾`.
- Right-hand detail strip is omitted.
- Main area shows the existing empty branch with copy updated from "Select a project from the left." to "No active project." (and the "Not registered — cd into the directory to activate." branch is kept verbatim).

Dropdown panel (when `<details open>`):

```
┌─────────────────────────────────────────────┐
│ dotfiles                          ●healthy  │  ← .project-row.active
│   ~/workspace/.../dotfiles                  │
├─────────────────────────────────────────────┤
│ other-proj                        ●spawning │
│   ~/workspace/.../other                     │
└─────────────────────────────────────────────┘
```

Each row is a `<a class="project-row" href="/?project=<key>">`. Active row gets `.active`. Two-row CSS grid: name (top-left) / path (bottom-left) / badge (right, spans both rows).

## File-level changes

### `crates/beansd/src/web/templates/index.html`

- Remove the `<nav>` block entirely.
- Replace it with a `<header id="topbar" hx-get="/partials/topbar?active={% if let Some(k) = active_key %}{{ k.display() }}{% endif %}" hx-trigger="every 5s">{% include "top_bar.html" %}</header>`.
- `<main>` keeps the iframe-or-empty branch AND the heartbeat `<form>`. The heartbeat must NOT move into `top_bar.html`: the 5s htmx swap on the bar would destroy and recreate the form every cycle, resetting its 15s trigger and preventing it from ever firing.
- Update the empty-state copy: "Select a project from the left." → "No active project."

### `crates/beansd/src/web/templates/top_bar.html` (new)

Renders the bar in full. Structure:

```html
<details class="project-switcher">
  <summary>
    {% if let Some(p) = active_project %}{{ p.display_name }}{% else %}Select a project{% endif %}
    <span class="caret">▾</span>
  </summary>
  <div class="panel">
    {% for p in projects %}
    <a class="project-row{% if Some(p.key.clone()) == active_key %} active{% endif %}"
       href="/?project={{ p.key.display() }}">
      <div class="name">{{ p.display_name }}</div>
      <div class="path">{{ p.key.display() }}</div>
      <span class="badge {{ p.state }}">{{ p.state }}</span>
    </a>
    {% endfor %}
  </div>
</details>
{% if let Some(p) = active_project %}
<div class="topbar-detail">
  <span class="badge {{ p.state }}">{{ p.state }}</span>
  <span class="path">{{ p.key.display() }}</span>
  {% if let Some(port) = p.port %}<span class="port">:{{ port }}</span>{% endif %}
</div>
{% endif %}
```

### `crates/beansd/src/web/templates/project_list.html`

Delete. Its content is folded into `top_bar.html`'s `.panel`.

### `crates/beansd/src/web/routes/html/projects.rs`

- Rename `ProjectListPartial` → `TopBarPartial`. Fields: `projects: Vec<ProjectView>`, `active_key: Option<PathBuf>`, `active_project: Option<ProjectView>`. Template path: `top_bar.html`.
- Rename route `/partials/projects` → `/partials/topbar`. Handler builds all three fields, using the new helper described below.
- `IndexTemplate` keeps its three fields (`projects`, `active_key`, `active_project`). The `index` handler keeps its current logic but now relies on the same helper for `active_project`.
- Tests:
  - Rename `partial_returns_ok_for_empty_registry` to target `/partials/topbar`.
  - Rename `partial_lists_registered_projects` to target `/partials/topbar`. Assert it contains `healthy`, `:4242`, AND `/tmp/p` (the new path-in-row expectation).
  - Update `index_renders_empty_state` to assert "No active project" instead of "Select a project".
  - Add `index_with_active_project_shows_detail_strip`: seed a healthy project, request `/?project=/tmp/p`, assert body contains the path string outside of just the dropdown panel (sufficient: assert it appears twice — once in the row, once in the detail strip).

### `crates/beansd/src/web/views.rs`

- Keep `ProjectView` and `project_views` unchanged.
- Add `pub(in crate::web) fn resolve_active(projects: &[ProjectView], key: Option<&Path>) -> Option<ProjectView>` that returns the project matching `key` only if `port.is_some()` (same predicate the `index` handler uses today inline). Both `index` and `topbar_partial` call it.

### `crates/beansd/src/web/static/app.css`

Replace the whole file. Key rules:

- `body { font-family: ...; height: 100vh; display: grid; grid-template-rows: 40px 1fr; }` (was `grid-template-columns: 280px 1fr`).
- `#topbar { background: #1e1e2e; color: #cdd6f4; padding: 0 1rem; display: flex; align-items: center; gap: 1rem; }`.
- `details.project-switcher { position: relative; }`.
- `details.project-switcher > summary { list-style: none; padding: 0.35rem 0.6rem; border-radius: 4px; cursor: pointer; } details.project-switcher > summary::-webkit-details-marker { display: none; } details.project-switcher > summary:hover { background: #313244; }`.
- `.caret { opacity: 0.6; margin-left: 0.3rem; }`.
- `details[open] > .panel { position: absolute; top: 100%; left: 0; min-width: 280px; max-width: 480px; background: #1e1e2e; border: 1px solid #313244; border-radius: 4px; z-index: 10; max-height: 60vh; overflow-y: auto; margin-top: 0.25rem; }`.
- `.project-row { display: grid; grid-template-columns: 1fr auto; column-gap: 0.75rem; padding: 0.5rem 0.75rem; color: inherit; text-decoration: none; }`.
- `.project-row .name { grid-column: 1; grid-row: 1; font-weight: 500; }`.
- `.project-row .path { grid-column: 1; grid-row: 2; font-family: ui-monospace, monospace; font-size: 0.7rem; opacity: 0.6; }`.
- `.project-row .badge { grid-column: 2; grid-row: 1 / 3; align-self: center; }`.
- `.project-row:hover { background: #313244; }`.
- `.project-row.active { background: #45475a; }`.
- `.topbar-detail { display: flex; align-items: center; gap: 0.75rem; margin-left: auto; min-width: 0; }`.
- `.topbar-detail .path { font-family: ui-monospace, monospace; font-size: 0.8rem; opacity: 0.7; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }`.
- `.topbar-detail .port { font-family: ui-monospace, monospace; font-size: 0.8rem; opacity: 0.7; }`.
- Badges: keep existing `.badge`, `.badge.healthy`, `.badge.spawning`, `.badge.dead` rules. Add `.badge.evicting { background: #fab387; color: #1e1e2e; }` (catppuccin peach) since `views.rs` already emits that state string but no rule exists today.
- `main { display: flex; flex-direction: column; }`, `main iframe { flex: 1; border: none; width: 100% }`, `main .empty { display: flex; align-items: center; justify-content: center; height: 100%; opacity: 0.5 }` — unchanged.

## Data flow

No changes to the registry or supervisor. The bar is a pure read view over `Registry`:

1. Browser navigates to `/?project=<key>` → `index` handler locks the registry, calls `project_views(&reg)`, calls `resolve_active(&projects, q.project.as_deref())`, renders `IndexTemplate` → which `{% include "top_bar.html" %}`.
2. Every 5s, `#topbar` issues `GET /partials/topbar?active=<key>` → handler does the same three steps, renders `TopBarPartial` (same template), htmx swaps the bar's inner HTML.
3. Open `<details>` state is held in the DOM; an htmx swap that replaces the bar's contents will close it on the next tick. Acceptable: switching projects via the dropdown navigates the whole page anyway, and the 5s poll is fast enough that re-opening is rare.

## Heartbeat

The `<form hx-post="/api/heartbeat" ...>` element stays in `<main>` exactly where it lives today. It must not move into `top_bar.html`, because the 5s htmx swap on `#topbar` would destroy the form before its 15s trigger fires, leaving the project without heartbeats and triggering eviction. `<main>` is not polled-swapped, so the form's timer accumulates correctly.

## Acceptance criteria

- `nix flake check` passes (compiles, all tests including the renamed/added ones pass).
- Loading `/` with no `?project=` shows: top bar with summary text "Select a project ▾", no right-hand detail strip, main area shows "No active project."
- Loading `/?project=<healthy-key>` shows: summary text is the project's display name, right-hand strip shows healthy badge + path + `:port`, main area shows the iframe.
- Opening the dropdown reveals one row per registered project with name, path (mono), and a status badge. Active row is visually highlighted.
- Clicking a row navigates to `/?project=<that-key>`.
- After 5 seconds, the bar refreshes via htmx; status badges/port values reflect any registry changes since.
- Manual smoke: open localhost wrapper, register a second project, confirm it appears in the dropdown within 5s without a full reload.
