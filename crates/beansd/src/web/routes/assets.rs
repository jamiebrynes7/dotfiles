use crate::web::State;
use axum::Router;

pub(super) fn router() -> Router<State> {
    Router::new()
}
