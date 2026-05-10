use crate::registry::Registry;
use askama::Template;
use axum::http::header;
use axum::response::IntoResponse;
use axum::{Router, routing::get};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;

const HTMX_JS: &[u8] = include_bytes!("../static/htmx.min.js");
const APP_CSS: &str = include_str!("../static/app.css");

#[derive(Clone)]
pub struct LauncherState {
    pub registry: Arc<Mutex<Registry>>,
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

async fn index(
    axum::extract::Query(q): axum::extract::Query<IndexQuery>,
    axum::extract::State(state): axum::extract::State<LauncherState>,
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

async fn projects_partial(
    axum::extract::Query(q): axum::extract::Query<PartialQuery>,
    axum::extract::State(state): axum::extract::State<LauncherState>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: q.active,
    };
    axum::response::Html(tmpl.render().unwrap())
}

async fn serve_htmx() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript")], HTMX_JS)
}

async fn serve_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css")], APP_CSS)
}

pub fn router_with_state(state: LauncherState) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/partials/projects", get(projects_partial))
        .route("/static/htmx.min.js", get(serve_htmx))
        .route("/static/app.css", get(serve_css))
        .with_state(state)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    fn empty_state() -> LauncherState {
        LauncherState {
            registry: Arc::new(Mutex::new(Registry::new())),
        }
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
        use std::time::Instant;

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
        let state = LauncherState { registry };
        let app = router_with_state(state);
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
}
