# beansd `web/` module refactor — spec

Date: 2026-05-24

Refactor `crates/beansd/src/launcher.rs` into a `crates/beansd/src/web/`
module. The module exposes a `Server` type (bind + serve) and groups its
routes by HTML vs API with resource-level files inside each.

## Goals

- Replace the single `launcher.rs` file with a `web/` module whose public
  surface is a `Server` type, not a router builder.
- Group routes by response style (HTML vs API) with resource-level files
  inside each group; assets are their own file.
- Move the askama templates and static assets under `src/web/` so all
  web-specific files live together.
- Preserve current behavior: same routes, same handlers, same tests pass.

## Non-goals

- No new routes, no behavior changes to existing handlers.
- No changes to `Daemon`, `Registry`, `Supervisor`, or `Evictor`.
- No changes to the UDS RPC server.
- No introduction of `rustfmt.toml` / `clippy.toml` / `[workspace.lints]`.
- No renaming the `launcher_port` config field (it's serialized into
  user-facing TOML).

## Public API

`crates/beansd/src/web/mod.rs` exposes one type:

```rust
pub struct Server { /* private */ }

impl Server {
    /// Binds a TCP listener on 127.0.0.1:`port` and constructs the server.
    /// Surface address-in-use and similar errors here so `run()` can fail
    /// before spawning any tasks.
    pub async fn bind(
        registry: Arc<Mutex<Registry>>,
        daemon: Arc<Daemon>,
        port: u16,
    ) -> anyhow::Result<Self>;

    pub fn local_addr(&self) -> SocketAddr;

    /// Consumes the server and serves until the listener errors.
    /// Returned future is `Send + 'static` so callers can `tokio::spawn` it.
    pub fn serve(self) -> impl Future<Output = std::io::Result<()>> + Send + 'static;
}
```

`LauncherState` is renamed `State`, kept private to `web/`. Tests inside
`web/` build `State` directly and exercise the merged router; nothing
outside `web/` references `State`.

## File layout

```
crates/beansd/
  askama.toml                 NEW: [general] dirs = ["src/web/templates"]
  src/
    main.rs                   mod launcher; → mod web;
    run.rs                    uses web::Server (see below)
    web/
      mod.rs                  pub struct Server; impl Server { bind, local_addr, serve };
                              pub(in crate::web) struct State { registry, daemon } (visible
                              inside web/, not outside); private fn router(state: State) -> Router
                              merging routes::router()
      views.rs                pub(in crate::web) struct ProjectView;
                              pub(in crate::web) fn project_views(&Registry) -> Vec<ProjectView>
                              (same rationale as State: descendants need it, outside does not)
      templates/              moved from crates/beansd/templates/
        index.html
        project_list.html
      static/                 moved from crates/beansd/static/
        htmx.min.js
        app.css
      routes/
        mod.rs                pub(super) fn router() -> Router<State> merging html, api, assets
        html/
          mod.rs              pub(super) fn router() -> Router<State> merging projects
          projects.rs         IndexTemplate, IndexQuery, index handler (`GET /`)
                              ProjectListPartial, PartialQuery, projects_partial handler
                              (`GET /partials/projects`)
                              tests
        api/
          mod.rs              pub(super) fn router() -> Router<State> merging projects + heartbeat
          projects.rs         KeyForm, start_project (`POST /api/projects/start`),
                              stop_project (`POST /api/projects/stop`); both return
                              ProjectListPartial — import via
                              `use super::super::html::projects::ProjectListPartial;`
                              tests
          heartbeat.rs        KeyForm reuse via `pub(super)` from api/projects.rs (or its
                              own local copy — see "Open call" below), heartbeat handler
                              (`POST /api/heartbeat`)
                              tests
        assets.rs             const HTMX_JS / APP_CSS via include_*!("../static/..."),
                              serve_htmx, serve_css, tests
```

## Change checklist

### Move files

1. `git mv crates/beansd/templates crates/beansd/src/web/templates`
2. `git mv crates/beansd/static    crates/beansd/src/web/static`
3. Create `crates/beansd/askama.toml`:
   ```toml
   [general]
   dirs = ["src/web/templates"]
   ```

### New / restructured rust files

4. Delete `crates/beansd/src/launcher.rs`.
5. Create the `web/` module tree per the file layout above. Splitting
   `launcher.rs` is a transcription, not a rewrite:
   - `ProjectView` + `project_views` → `web/views.rs`, both
     `pub(in crate::web)`. The function takes `&Registry` and returns
     `Vec<ProjectView>` (signature unchanged).
   - `IndexTemplate` / `IndexQuery` / `index` → `web/routes/html/projects.rs`.
   - `ProjectListPartial` / `PartialQuery` / `projects_partial` →
     `web/routes/html/projects.rs` (same file as `index` — both are
     `/`-page concerns).
   - `KeyForm` / `stop_project` / `start_project` → `web/routes/api/projects.rs`.
   - `KeyForm` / `heartbeat` → `web/routes/api/heartbeat.rs`.
   - `serve_htmx` / `serve_css` + the two `include_*!` consts →
     `web/routes/assets.rs`.
6. `web/mod.rs`:
   - Declare `mod views; mod routes;`.
   - Define `pub(in crate::web) struct State { pub(in crate::web) registry: Arc<Mutex<Registry>>, pub(in crate::web) daemon: Arc<Daemon> }` and derive `Clone`. The `pub(in crate::web)` scope means descendants like `web/routes/html/projects.rs` can name and construct `State`, but nothing outside `web/` can.
   - Define `fn router(state: State) -> Router` that calls
     `routes::router().with_state(state)`.
   - Define `pub struct Server { listener: TcpListener, router: Router }` (or
     equivalent) and implement `bind`, `local_addr`, `serve`. `bind` builds
     `State` from its arguments, calls the private `router(state)`, binds
     `127.0.0.1:port` with `tokio::net::TcpListener::bind`, and returns the
     constructed `Server`. `serve(self)` runs `axum::serve(self.listener, self.router).await`.
7. Each subdir `mod.rs` exposes `pub(super) fn router() -> Router<State>`
   that wires the routes in that subdir using `axum::Router::new().route(...)`.
   These routers are typed `Router<State>` (state not yet bound); `web::router`
   binds the state once at the top.

### Wire-up changes

8. `crates/beansd/src/main.rs`: `mod launcher;` → `mod web;`.
9. `crates/beansd/src/run.rs`:
   - Remove `use crate::launcher::{router_with_state, LauncherState};`.
   - Add `use crate::web;`.
   - Remove the freestanding `let launcher_addr = ...; let tcp = ...;` and the
     `let app = router_with_state(LauncherState { ... });` block.
   - Replace with:
     ```rust
     let server = web::Server::bind(
         registry.clone(),
         daemon.clone(),
         cfg.launcher_port,
     ).await?;
     tracing::info!(addr = %server.local_addr(), "HTTP launcher bound");
     let http_task = tokio::spawn(server.serve());
     ```
   - The `tracing::info!(%launcher_addr, "HTTP launcher bound")` log line
     becomes `addr = %server.local_addr()` — same intent, drawn from the
     actual bound address.

### Tests

10. Each `routes/<group>/<resource>.rs` file owns the tests for its handlers,
    same as `launcher.rs` does today. Tests call the file's `pub(super) fn
    router()` (or its subdir's `mod.rs` `router()` — pick the smallest one
    that contains the handler under test), wrap it with `.with_state(state)`,
    and drive it via `tower::ServiceExt::oneshot`. The `build_state` /
    `empty_state` helpers in `launcher.rs` move next to whichever test file
    uses them most; if more than one file needs them, lift to a
    `pub(super) mod test_utils` in `web/mod.rs` (gated on `#[cfg(test)]`,
    per `crates/CLAUDE.md`).
11. The eight existing tests in `launcher.rs` move with the handlers they
    exercise:
    - `serves_htmx_with_js_content_type`, `serves_css_with_css_content_type`
      → `web/routes/assets.rs`.
    - `index_renders_empty_state`,
      `index_with_unknown_project_query_shows_not_registered`,
      `partial_returns_ok_for_empty_registry`,
      `partial_lists_registered_projects`
      → `web/routes/html/projects.rs`.
    - `heartbeat_returns_204_and_bumps_last_used` → `web/routes/api/heartbeat.rs`.
    - `stop_returns_partial_html` → `web/routes/api/projects.rs`.
12. No new tests required. The refactor is intentionally behavior-preserving;
    `cargo test -p beansd` passing is the bar.

## Open call: shared `KeyForm`

`launcher.rs` declares `KeyForm` once (line 105) and three handlers
(`heartbeat`, `start_project`, `stop_project`) all use it. After the split,
`api/projects.rs` and `api/heartbeat.rs` both need a form-extractor type
with `{ key: PathBuf }`. Options:

- Define it once in `web/routes/api/mod.rs` as `pub(super) struct KeyForm`
  and import from both files. **Chosen.** It's a one-line type and the two
  files share it cleanly; one place to evolve.
- Redeclare locally in each file. Rejected — pointless duplication for an
  identical two-field struct.

`PartialQuery` and `IndexQuery` stay file-local to `html/projects.rs`
because they're each used by one handler.

## Validation

- `cargo build --workspace` from repo root — must succeed.
- `cargo test --workspace` — must pass with no new or skipped tests.
- `nix flake check` — what CI runs; must succeed.
- Manual smoke test: run `beansd` locally, hit `http://127.0.0.1:<port>/`
  in a browser, confirm the index page renders, `GET /partials/projects`
  returns the partial, `/static/htmx.min.js` and `/static/app.css` serve
  with the right content types, and at least one of `start_project` /
  `stop_project` round-trips correctly.

## Risk / rollback

- **Askama template path:** if `askama.toml` doesn't take effect, build
  fails loudly at the `#[template(path = "index.html")]` line with a "file
  not found" error. Fix-forward: confirm the `[general] dirs` form is right
  for the askama version in `Cargo.lock` (askama 0.12+ uses
  `[general] dirs = [...]`; older versions use `[general] template_dirs`).
- **`include_*!` paths:** wrong relative depth → compile-time error pointing
  at the exact macro call. Trivially fixable.
- **`Server::serve` future bounds:** if the returned future isn't `Send +
  'static`, `tokio::spawn` rejects it at compile time. The `Router<State>`
  type and `axum::serve` already give us a `Send + 'static` future, so this
  is structural, not a runtime risk.
- **Rollback:** the change is a pure code reorg with no schema, no on-disk
  format, no protocol surface. Revert the commit if anything goes wrong.

## Out of scope follow-ups

- Splitting `State` into its own file (`web/state.rs`) — only worth doing
  once `State` grows past two fields.
- A dedicated `web/templates.rs` rust module — only worth doing if a future
  partial needs to be rendered from multiple handler files and the
  `super::super::html::projects` import path becomes a pain.
- Integration-level tests under `crates/beansd/tests/` that drive
  `web::Server` end-to-end (currently tests target the merged router via
  `oneshot`; that's appropriate for the surface).
