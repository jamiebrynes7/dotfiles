use crate::web::State;
use axum::Router;

mod heartbeat;
mod projects;

pub(super) fn router() -> Router<State> {
    Router::new()
        .merge(projects::router())
        .merge(heartbeat::router())
}
