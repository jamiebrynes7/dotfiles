use crate::web::State;
use axum::Router;

mod projects;

pub(super) fn router() -> Router<State> {
    Router::new().merge(projects::router())
}
