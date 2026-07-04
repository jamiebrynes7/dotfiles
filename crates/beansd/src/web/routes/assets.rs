use crate::web::State;
use axum::http::header;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;

const HTMX_JS: &[u8] = include_bytes!("../static/htmx.min.js");
const APP_CSS: &str = include_str!("../static/app.css");
const FAVICON_SVG: &str = include_str!("../static/favicon.svg");

async fn serve_htmx() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript")], HTMX_JS)
}

async fn serve_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css")], APP_CSS)
}

async fn serve_favicon() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "image/svg+xml")], FAVICON_SVG)
}

pub(super) fn router() -> Router<State> {
    Router::new()
        .route("/static/htmx.min.js", get(serve_htmx))
        .route("/static/app.css", get(serve_css))
        .route("/static/favicon.svg", get(serve_favicon))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::web::test_utils::empty_state;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn serves_htmx_with_js_content_type() {
        let app = router().with_state(empty_state());
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
        let app = router().with_state(empty_state());
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
    async fn serves_favicon_with_svg_content_type() {
        let app = router().with_state(empty_state());
        let resp = app
            .oneshot(
                Request::get("/static/favicon.svg")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(resp.headers().get("content-type").unwrap(), "image/svg+xml");
    }
}
