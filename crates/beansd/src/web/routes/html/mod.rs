use crate::web::State;
use axum::Router;

pub(super) mod projects;

pub(super) fn router() -> Router<State> {
    Router::new().merge(projects::router())
}
