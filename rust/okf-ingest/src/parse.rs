//! Frontmatter parsing + body normalization — mirrors `py/okf/okf.py::parse_file`.
//!
//! Parity notes:
//! - Lines are split like Python `splitlines()` / R `readLines()`: the EOL is
//!   stripped (including a trailing newline, and the CR of CRLF), so the body —
//!   and therefore `content_hash` — is byte-identical across bindings.
//! - YAML is loaded with yaml-rust2 (YAML 1.2 core schema): there is no
//!   timestamp tag, so `timestamp: 2026-06-22T00:00:00Z` stays a verbatim
//!   string with no custom-loader work (the Python binding strips the resolver
//!   explicitly; see `_OKFLoader`).

use sha1::{Digest, Sha1};
use yaml_rust2::yaml::Hash;
use yaml_rust2::{Yaml, YamlLoader};

/// Result of parsing one document's text.
#[derive(Debug)]
pub struct Parsed {
    pub meta: Option<Hash>,
    pub body: String,
    /// `no_frontmatter` | `unclosed_frontmatter` | `yaml_parse_error`.
    pub err: Option<&'static str>,
}

fn is_fence(line: &str) -> bool {
    // ^---\s*$
    line.strip_prefix("---")
        .is_some_and(|rest| rest.trim().is_empty())
}

/// Parse frontmatter + body from raw file text.
pub fn parse_text(text: &str) -> Parsed {
    // str::lines() == Python splitlines() for \n and \r\n (strips trailing
    // newline; no phantom empty final line).
    let raw: Vec<&str> = text.lines().collect();
    let txt = raw.join("\n");
    let mut i = 0;
    while i < raw.len() && raw[i].trim().is_empty() {
        i += 1;
    }
    if i >= raw.len() || !is_fence(raw[i]) {
        return Parsed {
            meta: None,
            body: txt,
            err: Some("no_frontmatter"),
        };
    }
    let opn = i;
    let close = match (opn + 1..raw.len()).find(|&j| is_fence(raw[j])) {
        Some(c) => c,
        None => {
            return Parsed {
                meta: None,
                body: txt,
                err: Some("unclosed_frontmatter"),
            }
        }
    };
    let fm = raw[opn + 1..close].join("\n");
    let body = if close < raw.len() - 1 {
        raw[close + 1..].join("\n")
    } else {
        String::new()
    };
    let meta = match YamlLoader::load_from_str(&fm) {
        Ok(docs) => docs.into_iter().next(),
        Err(_) => None,
    };
    match meta {
        Some(Yaml::Hash(h)) => Parsed {
            meta: Some(h),
            body,
            err: None,
        },
        _ => Parsed {
            meta: None,
            body,
            err: Some("yaml_parse_error"),
        },
    }
}

/// sha1 hex of the normalized body (the cross-language parity lock).
pub fn content_hash(body: &str) -> String {
    let digest = Sha1::digest(body.as_bytes());
    digest.iter().fold(String::with_capacity(40), |mut s, b| {
        use std::fmt::Write;
        let _ = write!(s, "{b:02x}");
        s
    })
}

/// Scalar-to-string coercion — the `_s()` of the Python binding: `None` for
/// sequences/mappings/null, otherwise the scalar as a string. yaml-rust2 keeps
/// the raw text of floats (`0.1` stays `"0.1"`), matching Python `str(0.1)`.
pub fn scalar_str(y: &Yaml) -> Option<String> {
    match y {
        Yaml::String(s) => Some(s.clone()),
        Yaml::Real(s) => Some(s.clone()),
        Yaml::Integer(i) => Some(i.to_string()),
        Yaml::Boolean(b) => Some(b.to_string()),
        _ => None,
    }
}

/// YAML value -> JSON value (for `tags` and the `frontmatter` column). The
/// JSON serialization of `tags` is what lexical seeding matches against.
pub fn yaml_to_json(y: &Yaml) -> serde_json::Value {
    use serde_json::Value;
    match y {
        Yaml::Null | Yaml::BadValue | Yaml::Alias(_) => Value::Null,
        Yaml::Boolean(b) => Value::Bool(*b),
        Yaml::Integer(i) => Value::from(*i),
        Yaml::Real(s) => match s.parse::<f64>() {
            Ok(f) => serde_json::Number::from_f64(f)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            Err(_) => Value::String(s.clone()),
        },
        Yaml::String(s) => Value::String(s.clone()),
        Yaml::Array(a) => Value::Array(a.iter().map(yaml_to_json).collect()),
        Yaml::Hash(h) => {
            let mut m = serde_json::Map::new();
            for (k, v) in h.iter() {
                let key = scalar_str(k).unwrap_or_default();
                m.insert(key, yaml_to_json(v));
            }
            Value::Object(m)
        }
    }
}

/// Fetch a frontmatter value by string key.
pub fn meta_get<'a>(h: &'a Hash, key: &str) -> Option<&'a Yaml> {
    h.get(&Yaml::String(key.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fence_matching() {
        assert!(is_fence("---"));
        assert!(is_fence("---  "));
        assert!(!is_fence("----"));
        assert!(!is_fence(" ---"));
        assert!(!is_fence("--- x"));
    }

    #[test]
    fn crlf_and_trailing_newline_normalize() {
        let unix = "---\ntype: Signal\n---\nbody line\n";
        let dos = "---\r\ntype: Signal\r\n---\r\nbody line\r\n";
        let p1 = parse_text(unix);
        let p2 = parse_text(dos);
        assert_eq!(p1.body, "body line");
        assert_eq!(p1.body, p2.body);
        assert_eq!(content_hash(&p1.body), content_hash(&p2.body));
    }

    #[test]
    fn no_frontmatter_and_unclosed() {
        assert_eq!(parse_text("just text").err, Some("no_frontmatter"));
        assert_eq!(parse_text("---\ntype: X").err, Some("unclosed_frontmatter"));
        assert_eq!(
            parse_text("---\n- a\n- b\n---\nx").err,
            Some("yaml_parse_error")
        );
    }

    #[test]
    fn timestamp_stays_verbatim() {
        let p = parse_text("---\ntimestamp: 2026-06-22T00:00:00Z\n---\nx");
        let m = p.meta.unwrap();
        let v = meta_get(&m, "timestamp").unwrap();
        assert_eq!(scalar_str(v).as_deref(), Some("2026-06-22T00:00:00Z"));
    }

    #[test]
    fn float_scalar_keeps_raw_text() {
        let p = parse_text("---\nokf_version: 0.1\n---\nx");
        let m = p.meta.unwrap();
        assert_eq!(
            scalar_str(meta_get(&m, "okf_version").unwrap()).as_deref(),
            Some("0.1")
        );
    }
}
