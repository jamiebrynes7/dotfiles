use crate::web::views::{project_views, ProjectView};
use crate::web::State;
use askama::Template;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use std::path::PathBuf;

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
    axum::extract::State(state): axum::extract::State<State>,
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
pub(in crate::web) struct ProjectListPartial {
    pub(in crate::web) projects: Vec<ProjectView>,
    pub(in crate::web) active_key: Option<PathBuf>,
}

#[derive(serde::Deserialize)]
struct PartialQuery {
    active: Option<PathBuf>,
}

async fn projects_partial(
    axum::extract::Query(q): axum::extract::Query<PartialQuery>,
    axum::extract::State(state): axum::extract::State<State>,
) -> impl IntoResponse {
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: q.active,
    };
    axum::response::Html(tmpl.render().unwrap())
}

pub(super) fn router() -> Router<State> {
    Router::new()
        .route("/", get(index))
        .route("/partials/projects", get(projects_partial))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::{self, Project, ProjectState, Registry};
    use crate::spawner::testing::FakeChildHandle;
    use crate::web::test_utils::{build_state, empty_state};
    use axum::http::{Request, StatusCode};
    use std::sync::Arc;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    #[tokio::test]
    async fn index_renders_empty_state() {
        let app = router().with_state(empty_state());
        let resp = app
            .oneshot(Request::get("/").body(axum::body::Body::empty()).unwrap())
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
    async fn index_with_unknown_project_query_shows_not_registered() {
        let app = router().with_state(empty_state());
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
    async fn partial_returns_ok_for_empty_registry() {
        let app = router().with_state(empty_state());
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
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/p".into(),
                "p".into(),
                ProjectState::Healthy {
                    port: 4242,
                    child: Box::new(FakeChildHandle::new(1)),
                },
            )],
        );
        let app = router().with_state(build_state(Arc::new(Mutex::new(r))));
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
}
