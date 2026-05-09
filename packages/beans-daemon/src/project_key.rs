use std::path::{Path, PathBuf};

/// Walk up from `start` looking for `.beans.yml`. Returns the abs path of
/// the directory containing it, or `None` if no such ancestor exists.
pub fn resolve(start: &Path) -> std::io::Result<Option<PathBuf>> {
    let mut current = std::fs::canonicalize(start)?;
    loop {
        if current.join(".beans.yml").is_file() {
            return Ok(Some(current));
        }
        match current.parent() {
            Some(parent) => current = parent.to_path_buf(),
            None => return Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn finds_marker_in_starting_dir() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join(".beans.yml"), "").unwrap();
        let key = resolve(dir.path()).unwrap().unwrap();
        assert_eq!(key, std::fs::canonicalize(dir.path()).unwrap());
    }

    #[test]
    fn finds_marker_in_ancestor() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join(".beans.yml"), "").unwrap();
        let nested = dir.path().join("a/b/c");
        std::fs::create_dir_all(&nested).unwrap();
        let key = resolve(&nested).unwrap().unwrap();
        assert_eq!(key, std::fs::canonicalize(dir.path()).unwrap());
    }

    #[test]
    fn returns_none_when_no_marker() {
        let dir = tempdir().unwrap();
        let key = resolve(dir.path()).unwrap();
        assert!(key.is_none());
    }

    #[test]
    fn errors_if_start_doesnt_exist() {
        assert!(resolve(Path::new("/no/such/path/at/all")).is_err());
    }
}
