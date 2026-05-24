use crate::web::State;
use axum::Router;
use std::path::PathBuf;

mod heartbeat;
mod projects;

#[derive(serde::Deserialize)]
pub(super) struct KeyForm {
    pub(super) key: PathBuf,
}

pub(super) fn router() -> Router<State> {
    Router::new()
        .merge(projects::router())
        .merge(heartbeat::router())
}
