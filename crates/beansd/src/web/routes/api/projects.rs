use super::super::html::projects::ProjectListPartial;
use crate::web::views::project_views;
use crate::web::State;
use askama::Template;
use axum::response::IntoResponse;
use axum::routing::post;
use axum::Router;
use beansd_rpc::Handler;

async fn start_project(
    axum::extract::State(state): axum::extract::State<State>,
    axum::Form(f): axum::Form<super::KeyForm>,
) -> axum::response::Response {
    if state.daemon.start(f.key).await.is_err() {
        return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: None,
    };
    axum::response::Html(tmpl.render().unwrap()).into_response()
}

async fn stop_project(
    axum::extract::State(state): axum::extract::State<State>,
    axum::Form(f): axum::Form<super::KeyForm>,
) -> axum::response::Response {
    if state.daemon.stop(f.key).await.is_err() {
        return axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let reg = state.registry.lock().await;
    let tmpl = ProjectListPartial {
        projects: project_views(&reg),
        active_key: None,
    };
    axum::response::Html(tmpl.render().unwrap()).into_response()
}

pub(super) fn router() -> Router<State> {
    Router::new()
        .route("/api/projects/start", post(start_project))
        .route("/api/projects/stop", post(stop_project))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::{self, Project, ProjectState, Registry};
    use crate::web::test_utils::build_state;
    use axum::http::{Request, StatusCode};
    use std::sync::Arc;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    #[tokio::test]
    async fn stop_returns_partial_html() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/y".into(),
                "y".into(),
                ProjectState::Spawning,
            )],
        );
        let registry = Arc::new(Mutex::new(r));

        let app = router().with_state(build_state(registry));
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
