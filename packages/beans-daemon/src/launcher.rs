use axum::http::header;
use axum::response::IntoResponse;
use axum::{Router, routing::get};

const HTMX_JS: &[u8] = include_bytes!("../static/htmx.min.js");
const APP_CSS: &str = include_str!("../static/app.css");

async fn serve_htmx() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript")], HTMX_JS)
}

async fn serve_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css")], APP_CSS)
}

pub fn router() -> Router {
    Router::new()
        .route("/static/htmx.min.js", get(serve_htmx))
        .route("/static/app.css", get(serve_css))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn serves_htmx_with_js_content_type() {
        let app = router();
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
        let app = router();
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
}
