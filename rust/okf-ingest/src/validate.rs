//! OKF validation rules — mirrors `py/okf/okf.py::validate` verbatim.
//! Permissive consumption: recommended-field issues are warnings, only
//! unparseable frontmatter / missing type are errors.

use std::collections::BTreeSet;
use std::sync::OnceLock;

use regex::Regex;

use crate::links::links;
use crate::model::{Bundle, Finding, Severity};

fn re_iso() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$").unwrap())
}

pub fn validate(b: &Bundle) -> Vec<Finding> {
    let mut out: Vec<Finding> = Vec::new();
    let add = |out: &mut Vec<Finding>, path: &str, sev: Severity, rule: &str, msg: String| {
        out.push(Finding {
            path: path.to_string(),
            severity: sev,
            rule: rule.to_string(),
            message: msg,
        });
    };

    for c in &b.concepts {
        if c.reserved {
            continue;
        }
        if let Some(err) = &c.parse_error {
            add(
                &mut out,
                &c.path,
                Severity::Error,
                "frontmatter_unparseable",
                format!("no parseable frontmatter ({err})"),
            );
            continue;
        }
        if c.kind.as_deref().unwrap_or("").is_empty() {
            add(
                &mut out,
                &c.path,
                Severity::Error,
                "missing_type",
                "frontmatter has no non-empty type".to_string(),
            );
        }
        if c.title.is_none() {
            add(
                &mut out,
                &c.path,
                Severity::Warn,
                "missing_title",
                "recommended field title absent".to_string(),
            );
        }
        if c.description.is_none() {
            add(
                &mut out,
                &c.path,
                Severity::Warn,
                "missing_description",
                "recommended field description absent".to_string(),
            );
        }
        match &c.timestamp {
            None => add(
                &mut out,
                &c.path,
                Severity::Warn,
                "missing_timestamp",
                "recommended field timestamp absent".to_string(),
            ),
            Some(ts) if !re_iso().is_match(ts) => add(
                &mut out,
                &c.path,
                Severity::Warn,
                "timestamp_not_iso8601",
                format!("timestamp not ISO-8601: {ts}"),
            ),
            _ => {}
        }
    }

    let lk_all = links(b);
    for lk in &lk_all {
        if !lk.resolved {
            add(
                &mut out,
                &lk.src_path,
                Severity::Warn,
                "broken_link",
                format!("unresolved link: {}", lk.dst_raw),
            );
        }
    }

    // orphan concepts (Karpathy-style lint): non-reserved, parseable, no inbound link
    let inbound: BTreeSet<&str> = lk_all
        .iter()
        .filter_map(|l| l.dst_path.as_deref())
        .collect();
    for c in &b.concepts {
        if c.reserved || c.parse_error.is_some() {
            continue;
        }
        if !inbound.contains(c.path.as_str()) {
            add(
                &mut out,
                &c.path,
                Severity::Warn,
                "orphan",
                "no inbound links (orphan concept)".to_string(),
            );
        }
    }
    out
}
