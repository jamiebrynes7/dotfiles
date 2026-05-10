use crate::control::Daemon;
use crate::registry::Registry;
use crate::spawner::ChildSpawner;
use askama::Template;
use axum::http::header;
use axum::response::IntoResponse;
use axum::{Router, routing::get};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;

const HTMX_JS: &[u8] = include_bytes!("../static/htmx.min.js");
const APP_CSS: &str = include_str!("../static/app.css");

pub struct LauncherState<S: ChildSpawner + 'static> {
    pub registry: Arc<Mutex<Registry>>,
    pub daemon: Arc<Daemon<S>>,
}

// Manual Clone — we only clone Arcs, so don't require S: Clone.
impl<S: ChildSpawner + 'static> Clone for LauncherState<S> {
    fn clone(&self) -> Self {
        Self {
            registry: self.registry.clone(),
            daemon: self.daemon.clone(),
        }
    }
}

#[derive(Clone)]
struct ProjectView {
    key: PathBuf,
    display_name: String,
    state: &'static str,
    port: Option<u16>,
}

fn project_views(reg: &Registry) -> Vec<ProjectView> {
    use crate::registry::ProjectState;
    reg.iter()
        .map(|p| {
            let (state, port) = match &p.state {
                ProjectState::Spawning { .. } => ("spawning", None),
                ProjectState::Healthy { port, .. } => ("healthy", Some(*port)),
                ProjectState::Evicting { .. } => ("evicting", None),
                ProjectState::Dead { .. } => ("dead", None),
            };
            ProjectView {
                key: p.key.clone(),
                display_name: p.display_name.clone(),
                state,
                port,
            }
        })
        .collect()
}

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {
    projects: Vec<ProjectView>,
    active_key: Option<PathBuf>,
    active_project: Option<ProjectView>,
}

#[derive(serde::Deserialize)]
struct IndexQuery {
    project: Option<PathBuf>,
}

async fn index<S: ChildSpawner + 'static>(
    axum::extract::Query(q): axum::extract::Query<IndexQuery>,
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let projects = project_views(&reg);
    let active_project = q.project.as_ref().and_then(|k| {
        projects
            .iter()
            .find(|p| &p.key == k && p.port.is_some())
            .cloned()
    });
    let tmpl = IndexTemplate {
        projects,
        active_key: q.project,
        active_project,
    };
    axum::response::Html(tmpl.render().unwrap())
}

#[derive(Template)]
#[template(path = "project_list.html")]
struct ProjectListPartial {
    projects: Vec<ProjectView>,
    active_key: Option<PathBuf>,
}

#[derive(serde::Deserialize)]
struct PartialQuery {
    active: Option<PathBuf>,
}

async fn projects_partial<S: ChildSpawner + 'static>(
    axum::extract::Query(q): axum::extract::Query<PartialQuery>,
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: q.active,
    };
    axum::response::Html(tmpl.render().unwrap())
}

#[derive(serde::Deserialize)]
struct KeyForm {
    key: PathBuf,
}

async fn heartbeat<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    state.daemon.handle_heartbeat(f.key).await;
    axum::http::StatusCode::NO_CONTENT
}

async fn stop_project<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    state.daemon.handle_stop(f.key).await;
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: None,
    };
    axum::response::Html(tmpl.render().unwrap())
}

async fn start_project<S: ChildSpawner + 'static>(
    axum::extract::State(state): axum::extract::State<LauncherState<S>>,
    axum::Form(f): axum::Form<KeyForm>,
) -> impl IntoResponse {
    state.daemon.handle_start(f.key).await;
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: None,
    };
    axum::response::Html(tmpl.render().unwrap())
}

async fn serve_htmx() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript")], HTMX_JS)
}

async fn serve_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css")], APP_CSS)
}

pub fn router_with_state<S: ChildSpawner + 'static>(state: LauncherState<S>) -> Router {
    Router::new()
        .route("/", get(index::<S>))
        .route("/partials/projects", get(projects_partial::<S>))
        .route("/api/heartbeat", axum::routing::post(heartbeat::<S>))
        .route("/api/projects/start", axum::routing::post(start_project::<S>))
        .route("/api/projects/stop", axum::routing::post(stop_project::<S>))
        .route("/static/htmx.min.js", get(serve_htmx))
        .route("/static/app.css", get(serve_css))
        .with_state(state)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::spawner::ChildHandle;
    use crate::supervisor::Supervisor;
    use async_trait::async_trait;
    use axum::http::{Request, StatusCode};
    use std::collections::HashMap;
    use std::time::{Duration, Instant};
    use tower::ServiceExt;

    pub struct MockSpawner;
    #[async_trait]
    impl ChildSpawner for MockSpawner {
        async fn spawn(
            &self,
            _dir: &std::path::Path,
            _port: u16,
        ) -> anyhow::Result<Box<dyn ChildHandle>> {
            struct C;
            #[async_trait]
            impl ChildHandle for C {
                fn pid(&self) -> u32 {
                    0
                }
                async fn wait(&mut self) -> std::io::Result<String> {
                    std::future::pending().await
                }
                async fn send_sigterm(&mut self) -> std::io::Result<()> {
                    Ok(())
                }
                async fn send_sigkill(&mut self) -> std::io::Result<()> {
                    Ok(())
                }
            }
            Ok(Box::new(C))
        }
    }

    fn build_state(registry: Arc<Mutex<Registry>>) -> LauncherState<MockSpawner> {
        let supervisor = Arc::new(Supervisor {
            registry: registry.clone(),
            spawner: MockSpawner,
            health_timeout: Duration::from_secs(1),
            children: Arc::new(Mutex::new(HashMap::new())),
        });
        let daemon = Arc::new(Daemon {
            registry: registry.clone(),
            supervisor,
            lru_cap: 8,
            sigterm_grace: Duration::from_secs(5),
            sigkill_grace: Duration::from_secs(5),
            start_max_attempts: 1,
            start_base_backoff: Duration::from_millis(10),
        });
        LauncherState { registry, daemon }
    }

    fn empty_state() -> LauncherState<MockSpawner> {
        build_state(Arc::new(Mutex::new(Registry::new())))
    }

    #[tokio::test]
    async fn serves_htmx_with_js_content_type() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/static/htmx.min.js")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers().get("content-type").unwrap(),
            "application/javascript"
        );
    }

    #[tokio::test]
    async fn serves_css_with_css_content_type() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/static/app.css")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(resp.headers().get("content-type").unwrap(), "text/css");
    }

    #[tokio::test]
    async fn index_renders_empty_state() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = String::from_utf8(
            axum::body::to_bytes(resp.into_body(), 64 * 1024)
                .await
                .unwrap()
                .to_vec(),
        )
        .unwrap();
        assert!(body.contains("Select a project"));
    }

    #[tokio::test]
    async fn partial_returns_ok_for_empty_registry() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/partials/projects")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn partial_lists_registered_projects() {
        use crate::registry::ProjectState;

        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/p".into(), "p".into(), Instant::now())
            .unwrap();
        registry
            .lock()
            .await
            .transition_state(
                std::path::Path::new("/tmp/p"),
                ProjectState::Healthy {
                    port: 4242,
                    pid: 1,
                    spawned_at: Instant::now(),
                },
            )
            .unwrap();
        let app = router_with_state(build_state(registry));
        let resp = app
            .oneshot(
                Request::get("/partials/projects")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = String::from_utf8(
            axum::body::to_bytes(resp.into_body(), 64 * 1024)
                .await
                .unwrap()
                .to_vec(),
        )
        .unwrap();
        assert!(body.contains("healthy"));
        assert!(body.contains(":4242"));
    }

    #[tokio::test]
    async fn index_with_unknown_project_query_shows_not_registered() {
        let app = router_with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/?project=/tmp/missing")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = String::from_utf8(
            axum::body::to_bytes(resp.into_body(), 64 * 1024)
                .await
                .unwrap()
                .to_vec(),
        )
        .unwrap();
        assert!(body.contains("Not registered"));
    }

    #[tokio::test]
    async fn heartbeat_returns_204_and_bumps_last_used() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/x".into(), "x".into(), Instant::now())
            .unwrap();
        let before = registry
            .lock()
            .await
            .get(std::path::Path::new("/tmp/x"))
            .unwrap()
            .last_used;
        tokio::time::sleep(Duration::from_millis(20)).await;

        let app = router_with_state(build_state(registry.clone()));
        let resp = app
            .oneshot(
                Request::post("/api/heartbeat")
                    .header("content-type", "application/x-www-form-urlencoded")
                    .body(axum::body::Body::from("key=/tmp/x"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NO_CONTENT);

        let after = registry
            .lock()
            .await
            .get(std::path::Path::new("/tmp/x"))
            .unwrap()
            .last_used;
        assert!(after > before);
    }

    #[tokio::test]
    async fn stop_returns_partial_html() {
        let registry = Arc::new(Mutex::new(Registry::new()));
        registry
            .lock()
            .await
            .insert_spawning("/tmp/y".into(), "y".into(), Instant::now())
            .unwrap();

        let app = router_with_state(build_state(registry));
        let resp = app
            .oneshot(
                Request::post("/api/projects/stop")
                    .header("content-type", "application/x-www-form-urlencoded")
                    .body(axum::body::Body::from("key=/tmp/y"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }
}
