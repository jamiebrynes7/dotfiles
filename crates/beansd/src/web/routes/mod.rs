use crate::web::State;
use axum::Router;

mod api;
mod assets;
mod html;

pub(super) fn router() -> Router<State> {
    Router::new()
        .merge(html::router())
        .merge(api::router())
        .merge(assets::router())
}
