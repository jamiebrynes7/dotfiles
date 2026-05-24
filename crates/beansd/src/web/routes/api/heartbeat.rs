use crate::web::State;
use axum::response::IntoResponse;
use axum::routing::post;
use axum::Router;
use beansd_rpc::Handler;

async fn heartbeat(
    axum::extract::State(state): axum::extract::State<State>,
    axum::Form(f): axum::Form<super::KeyForm>,
) -> impl IntoResponse {
    match state.daemon.heartbeat(f.key).await {
        Ok(()) => axum::http::StatusCode::NO_CONTENT,
        Err(_) => axum::http::StatusCode::INTERNAL_SERVER_ERROR,
    }
}

pub(super) fn router() -> Router<State> {
    Router::new().route("/api/heartbeat", post(heartbeat))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::{self, Project, ProjectState, Registry};
    use crate::web::test_utils::build_state;
    use axum::http::{Request, StatusCode};
    use std::sync::Arc;
    use std::time::Duration;
    use tokio::sync::Mutex;
    use tower::ServiceExt;

    #[tokio::test]
    async fn heartbeat_returns_204_and_bumps_last_used() {
        let mut r = Registry::new();
        registry::test_utils::seed_registry(
            &mut r,
            vec![Project::new(
                "/tmp/x".into(),
                "x".into(),
                ProjectState::Spawning,
            )],
        );
        let registry = Arc::new(Mutex::new(r));
        let before = registry
            .lock()
            .await
            .get(std::path::Path::new("/tmp/x"))
            .unwrap()
            .last_used;
        tokio::time::sleep(Duration::from_millis(20)).await;

        let app = router().with_state(build_state(registry.clone()));
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
}
