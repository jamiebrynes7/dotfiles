use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
#[serde(tag = "op", content = "args", rename_all = "snake_case")]
pub enum Request {
    Cd { cwd: PathBuf },
    Ls {},
    Start { key: PathBuf },
    Stop { key: PathBuf },
    Status {},
    Heartbeat { key: PathBuf },
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum Response {
    Ok { ok: bool, data: serde_json::Value },
    Error { ok: bool, error: String },
}

impl Response {
    pub fn ok(data: serde_json::Value) -> Self {
        Response::Ok { ok: true, data }
    }

    pub fn err(msg: impl Into<String>) -> Self {
        Response::Error {
            ok: false,
            error: msg.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn round_trips_cd_request() {
        let r = Request::Cd {
            cwd: PathBuf::from("/abs/path"),
        };
        let s = serde_json::to_string(&r).unwrap();
        assert_eq!(s, r#"{"op":"cd","args":{"cwd":"/abs/path"}}"#);
        let back: Request = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn round_trips_ls_request_with_empty_args() {
        let r = Request::Ls {};
        let s = serde_json::to_string(&r).unwrap();
        assert_eq!(s, r#"{"op":"ls","args":{}}"#);
        let back: Request = serde_json::from_str(&s).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn ok_response_serialises_with_ok_true() {
        let s = serde_json::to_string(&Response::ok(json!({"x": 1}))).unwrap();
        assert!(s.contains(r#""ok":true"#));
        assert!(s.contains(r#""x":1"#));
    }

    #[test]
    fn err_response_serialises_with_ok_false() {
        let s = serde_json::to_string(&Response::err("boom")).unwrap();
        assert!(s.contains(r#""ok":false"#));
        assert!(s.contains(r#""error":"boom""#));
    }
}
