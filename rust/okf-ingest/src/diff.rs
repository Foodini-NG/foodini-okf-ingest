//! Deterministic concept-level diff — mirrors `py/okf/diff.py`.
//!
//! `git diff` shows text hunks; [`diff`] shows what changed as *knowledge
//! structure*: concepts added/removed, bodies changed (by `content_hash`),
//! frontmatter type/title changes, and graph deltas (edges added/removed,
//! links newly broken / fixed). Pure hash/set comparison, all output sorted.
//! Drift mode: `diff(DiffSide::Ingested(&ing), DiffSide::Dir(dir))` answers
//! "what drifted since the last ingest" without a catalog.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use crate::links::links;
use crate::model::{Bundle, Ingested, OkfError, SourceKind};
use crate::read::read_bundle;

/// One side of a diff.
pub enum DiffSide<'a> {
    Dir(&'a Path),
    Bundle(&'a Bundle),
    Ingested(&'a Ingested),
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ConceptMeta {
    kind: Option<String>,
    title: Option<String>,
    content_hash: String,
}

struct State {
    concepts: BTreeMap<String, ConceptMeta>,
    edges: BTreeSet<(String, String)>,
    broken: BTreeSet<(String, String)>,
}

fn state_of_bundle(b: &Bundle) -> State {
    let lk = links(b);
    state_from(b, &lk)
}

fn state_from(b: &Bundle, lk: &[crate::model::Link]) -> State {
    let concepts = b
        .concepts
        .iter()
        .map(|c| {
            (
                c.path.clone(),
                ConceptMeta {
                    kind: c.kind.clone(),
                    title: c.title.clone(),
                    content_hash: c.content_hash.clone(),
                },
            )
        })
        .collect();
    let edges = lk
        .iter()
        .filter(|l| l.resolved)
        .map(|l| (l.src_path.clone(), l.dst_path.clone().unwrap_or_default()))
        .collect();
    let broken = lk
        .iter()
        .filter(|l| !l.resolved)
        .map(|l| (l.src_path.clone(), l.dst_raw.clone()))
        .collect();
    State {
        concepts,
        edges,
        broken,
    }
}

fn bundle_state(x: &DiffSide<'_>) -> Result<State, OkfError> {
    match x {
        DiffSide::Dir(d) => {
            let b = read_bundle(d, None, SourceKind::Dir)?;
            Ok(state_of_bundle(&b))
        }
        DiffSide::Bundle(b) => Ok(state_of_bundle(b)),
        DiffSide::Ingested(ing) => Ok(state_from(&ing.bundle, &ing.links)),
    }
}

/// `{path, from, to}` for a changed frontmatter field.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldChange {
    pub path: String,
    pub from: Option<String>,
    pub to: Option<String>,
}

/// `(src_path, dst)` where dst is `dst_path` for edge deltas and `dst_raw`
/// for broken-link deltas.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EdgeDelta {
    pub src_path: String,
    pub dst: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiffSummary {
    pub added: usize,
    pub removed: usize,
    pub changed: usize,
    pub unchanged: usize,
    pub type_changed: usize,
    pub retitled: usize,
    pub links_added: usize,
    pub links_removed: usize,
    pub broken_added: usize,
    pub broken_fixed: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diff {
    pub identical: bool,
    pub added: Vec<String>,
    pub removed: Vec<String>,
    pub changed: Vec<String>,
    pub type_changed: Vec<FieldChange>,
    pub retitled: Vec<FieldChange>,
    pub links_added: Vec<EdgeDelta>,
    pub links_removed: Vec<EdgeDelta>,
    pub broken_added: Vec<EdgeDelta>,
    pub broken_fixed: Vec<EdgeDelta>,
    pub summary: DiffSummary,
}

fn field_diff<F>(
    common: &BTreeSet<&String>,
    ca: &BTreeMap<String, ConceptMeta>,
    cb: &BTreeMap<String, ConceptMeta>,
    get: F,
) -> Vec<FieldChange>
where
    F: Fn(&ConceptMeta) -> &Option<String>,
{
    let mut out = Vec::new();
    for p in common.iter() {
        let (x, y) = (get(&ca[*p]), get(&cb[*p]));
        if x != y {
            out.push(FieldChange {
                path: (*p).clone(),
                from: x.clone(),
                to: y.clone(),
            });
        }
    }
    out
}

fn pair_diff(a: &BTreeSet<(String, String)>, b: &BTreeSet<(String, String)>) -> Vec<EdgeDelta> {
    a.difference(b)
        .map(|(s, d)| EdgeDelta {
            src_path: s.clone(),
            dst: d.clone(),
        })
        .collect()
}

/// Concept-level diff between two states of an OKF knowledge base.
pub fn diff(a: DiffSide<'_>, b: DiffSide<'_>) -> Result<Diff, OkfError> {
    let sa = bundle_state(&a)?;
    let sb = bundle_state(&b)?;
    let (ca, cb) = (&sa.concepts, &sb.concepts);

    let ka: BTreeSet<&String> = ca.keys().collect();
    let kb: BTreeSet<&String> = cb.keys().collect();
    let added: Vec<String> = kb.difference(&ka).map(|p| (*p).clone()).collect();
    let removed: Vec<String> = ka.difference(&kb).map(|p| (*p).clone()).collect();
    let common: BTreeSet<&String> = ka.intersection(&kb).copied().collect();
    let changed: Vec<String> = common
        .iter()
        .filter(|p| ca[**p].content_hash != cb[**p].content_hash)
        .map(|p| (*p).clone())
        .collect();

    let type_changed = field_diff(&common, ca, cb, |m| &m.kind);
    let retitled = field_diff(&common, ca, cb, |m| &m.title);

    let links_added = pair_diff(&sb.edges, &sa.edges);
    let links_removed = pair_diff(&sa.edges, &sb.edges);
    let broken_added = pair_diff(&sb.broken, &sa.broken);
    let broken_fixed = pair_diff(&sa.broken, &sb.broken);

    let identical = added.is_empty()
        && removed.is_empty()
        && changed.is_empty()
        && type_changed.is_empty()
        && retitled.is_empty()
        && links_added.is_empty()
        && links_removed.is_empty()
        && broken_added.is_empty()
        && broken_fixed.is_empty();

    let summary = DiffSummary {
        added: added.len(),
        removed: removed.len(),
        changed: changed.len(),
        unchanged: common.len() - changed.len(),
        type_changed: type_changed.len(),
        retitled: retitled.len(),
        links_added: links_added.len(),
        links_removed: links_removed.len(),
        broken_added: broken_added.len(),
        broken_fixed: broken_fixed.len(),
    };
    Ok(Diff {
        identical,
        added,
        removed,
        changed,
        type_changed,
        retitled,
        links_added,
        links_removed,
        broken_added,
        broken_fixed,
        summary,
    })
}
