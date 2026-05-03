---
# dotfiles-6rb8
title: Project key resolution (`.beans.yml` upward search)
status: todo
type: task
created_at: 2026-05-03T14:34:36Z
updated_at: 2026-05-03T14:34:36Z
parent: dotfiles-yejq
---

**Files:**
- Create: `packages/beans-daemon/src/project_key.rs`
- Modify: `packages/beans-daemon/src/main.rs` (add `mod project_key;`)

The project key is the absolute path to the directory that contains the nearest `.beans.yml` walking up from a starting path. This module owns that resolution.

- [ ] **Step 1: Write the failing test**

Create `packages/beans-daemon/src/project_key.rs`:
```rust
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
            None         => return Ok(None),
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test project_key::`
Expected: FAIL — `mod project_key` not declared.

- [ ] **Step 3: Wire into main.rs**

Add `mod project_key;` to `packages/beans-daemon/src/main.rs`.

- [ ] **Step 4: Run tests**

Run: `cargo test project_key::`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/beans-daemon/src/project_key.rs packages/beans-daemon/src/main.rs
git commit -m "packages/beans-daemon: project key resolution via .beans.yml upward search"
```
