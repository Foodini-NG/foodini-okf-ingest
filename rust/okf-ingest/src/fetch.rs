//! Bundle materialization — mirrors `py/okf/okf.py::fetch` (`_source_kind`,
//! `_assert_safe_members`, `_bundle_root`), offline scope: local dir, local
//! tar/zip archive, or git URL via the `git` subprocess. Remote http(s)
//! archive download is not supported in this binding (document; the R and
//! Python bindings download).

use std::collections::BTreeSet;
use std::fs::File;
use std::path::{Component, Path, PathBuf};
use std::process::Command;

use flate2::read::GzDecoder;
use tempfile::TempDir;

use crate::model::{OkfError, SourceKind};

/// A materialized bundle directory. Holding the value keeps any temp dir
/// alive; it is removed on drop (the Python binding's `cleanup()` closure).
pub struct Fetched {
    pub dir: PathBuf,
    pub kind: SourceKind,
    _tmp: Option<TempDir>,
}

fn strip_query(source: &str) -> &str {
    let end = source.find(['?', '#']).unwrap_or(source.len());
    &source[..end]
}

fn source_kind(source: &str) -> Result<SourceKind, OkfError> {
    let s = strip_query(source);
    let ls = s.to_lowercase();
    if ls.ends_with(".zip") {
        return Ok(SourceKind::Zip);
    }
    if ls.ends_with(".tar.gz")
        || ls.ends_with(".tgz")
        || ls.ends_with(".tar")
        || ls.ends_with(".tar.bz2")
    {
        return Ok(SourceKind::Tar);
    }
    let host_is_forge = regex::Regex::new(r"^https?://(www\.)?(github|gitlab|bitbucket)\.")
        .unwrap()
        .is_match(s);
    if s.ends_with(".git") || source.starts_with("git@") || host_is_forge {
        return Ok(SourceKind::Git);
    }
    Err(OkfError::msg(format!(
        "cannot determine source kind (expected a dir, git URL, or tar/zip): {source}"
    )))
}

/// Reject archive members that would extract outside the target directory
/// (path traversal / zip-slip), before extracting anything.
fn assert_safe_member(name: &str) -> Result<(), OkfError> {
    let p = Path::new(name);
    for comp in p.components() {
        match comp {
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(OkfError::msg(format!(
                    "archive member escapes target dir (path traversal): {name:?}"
                )));
            }
            _ => {}
        }
    }
    Ok(())
}

/// Descend into a single wrapping directory (up to 6 levels) to find the
/// bundle root — archives usually wrap their content in one top-level dir.
fn bundle_root(base: &Path, subdir: Option<&str>) -> Result<PathBuf, OkfError> {
    if let Some(sd) = subdir {
        return Ok(base.join(sd));
    }
    let mut cur = base.to_path_buf();
    for _ in 0..6 {
        let mut has_md = false;
        let mut dirs: Vec<PathBuf> = Vec::new();
        for entry in std::fs::read_dir(&cur)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') {
                continue;
            }
            if name.to_lowercase().ends_with(".md") {
                has_md = true;
            }
            if entry.path().is_dir() {
                dirs.push(entry.path());
            }
        }
        if !has_md && dirs.len() == 1 {
            cur = dirs.remove(0);
        } else {
            break;
        }
    }
    Ok(cur)
}

fn extract_tar(local: &Path, dst: &Path) -> Result<(), OkfError> {
    let ls = local.to_string_lossy().to_lowercase();
    if ls.ends_with(".tar.bz2") {
        return Err(OkfError::msg(
            ".tar.bz2 is not supported by the Rust binding (use .tar.gz)",
        ));
    }
    let gz = ls.ends_with(".tar.gz") || ls.ends_with(".tgz");
    // Pass 1: safety check on all member names.
    let names: BTreeSet<String> = {
        let f = File::open(local)?;
        let mut entries_names = BTreeSet::new();
        if gz {
            let mut a = tar::Archive::new(GzDecoder::new(f));
            for e in a.entries()? {
                let e = e?;
                entries_names.insert(e.path()?.to_string_lossy().to_string());
            }
        } else {
            let mut a = tar::Archive::new(f);
            for e in a.entries()? {
                let e = e?;
                entries_names.insert(e.path()?.to_string_lossy().to_string());
            }
        }
        entries_names
    };
    for n in &names {
        assert_safe_member(n)?;
    }
    // Pass 2: extract.
    let f = File::open(local)?;
    if gz {
        tar::Archive::new(GzDecoder::new(f))
            .unpack(dst)
            .map_err(|e| OkfError::msg(format!("tar extract failed: {e}")))?;
    } else {
        tar::Archive::new(f)
            .unpack(dst)
            .map_err(|e| OkfError::msg(format!("tar extract failed: {e}")))?;
    }
    Ok(())
}

fn extract_zip(local: &Path, dst: &Path) -> Result<(), OkfError> {
    let f = File::open(local)?;
    let mut archive =
        zip::ZipArchive::new(f).map_err(|e| OkfError::msg(format!("zip open failed: {e}")))?;
    let names: Vec<String> = archive.file_names().map(str::to_string).collect();
    for n in &names {
        assert_safe_member(n)?;
    }
    archive
        .extract(dst)
        .map_err(|e| OkfError::msg(format!("zip extract failed: {e}")))?;
    Ok(())
}

/// Materialize a bundle from a dir, git URL, or local tar/zip archive.
pub fn fetch(
    source: &str,
    subdir: Option<&str>,
    branch: Option<&str>,
) -> Result<Fetched, OkfError> {
    let src_path = Path::new(source);
    if src_path.is_dir() {
        return Ok(Fetched {
            dir: std::fs::canonicalize(src_path)?,
            kind: SourceKind::Dir,
            _tmp: None,
        });
    }
    let kind = source_kind(source)?;
    if regex::Regex::new(r"^https?://").unwrap().is_match(source) && kind != SourceKind::Git {
        return Err(OkfError::msg(
            "remote archive download is not supported by the Rust binding; \
             fetch the archive locally first (git URLs are supported)",
        ));
    }
    let tmp = TempDir::with_prefix("okf_")?;
    let base = if kind == SourceKind::Git {
        let repo = tmp.path().join("repo");
        let mut cmd = Command::new("git");
        cmd.args(["clone", "--depth", "1"]);
        if let Some(b) = branch {
            cmd.args(["--branch", b]);
        }
        cmd.arg(source).arg(&repo);
        let status = cmd
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map_err(|e| OkfError::msg(format!("git clone failed (is git installed?): {e}")))?;
        if !status.success() {
            return Err(OkfError::msg(format!(
                "git clone failed (is git installed?): {source}"
            )));
        }
        repo
    } else {
        let ex = tmp.path().join("x");
        std::fs::create_dir_all(&ex)?;
        match kind {
            SourceKind::Zip => extract_zip(src_path, &ex)?,
            _ => extract_tar(src_path, &ex)?,
        }
        ex
    };
    let dir = bundle_root(&base, subdir)?;
    Ok(Fetched {
        dir,
        kind,
        _tmp: Some(tmp),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kind_detection() {
        assert_eq!(source_kind("x/b.zip").unwrap(), SourceKind::Zip);
        assert_eq!(source_kind("x/b.tar.gz").unwrap(), SourceKind::Tar);
        assert_eq!(source_kind("x/b.tgz").unwrap(), SourceKind::Tar);
        assert_eq!(
            source_kind("git@github.com:a/b.git").unwrap(),
            SourceKind::Git
        );
        assert_eq!(
            source_kind("https://github.com/a/b").unwrap(),
            SourceKind::Git
        );
        assert!(source_kind("what.is.this").is_err());
    }

    #[test]
    fn traversal_guard() {
        assert!(assert_safe_member("store/index.md").is_ok());
        assert!(assert_safe_member("../evil.md").is_err());
        assert!(assert_safe_member("/abs.md").is_err());
        assert!(assert_safe_member("a/../../evil.md").is_err());
    }
}
