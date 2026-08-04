//! Deterministic graph ranking — mirrors `py/okf/graph.py::seeds`/`ppr` and
//! `r/okf/R/okf_rank.R`.
//!
//! Exact power iteration (no Monte-Carlo sampling); floating-point parity with
//! the other bindings depends on the accumulation ORDER, which is pinned here:
//! edges iterate in sorted `(src, dst)` index order, dangling mass and the L1
//! convergence sum accumulate in ascending node index.

use std::collections::{BTreeSet, HashMap};
use std::sync::OnceLock;

use regex::Regex;

use crate::model::{Ingested, OkfError};

/// Fixed stopword list — byte-for-byte the `OKF_STOPWORDS` of
/// `py/okf/graph.py` / `r/okf/R/okf_rank.R`.
pub const OKF_STOPWORDS: [&str; 37] = [
    "the", "and", "for", "are", "was", "were", "with", "that", "this", "from", "how", "what",
    "when", "where", "which", "does", "did", "can", "could", "should", "would", "will", "has",
    "have", "had", "not", "its", "our", "your", "their", "about", "into", "over", "under", "why",
    "who", "whom",
];

fn re_token() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"[a-z0-9]+").unwrap())
}

#[derive(Debug, Clone, PartialEq)]
pub struct Seed {
    pub path: String,
    pub score: f64,
    pub title: Option<String>,
}

/// Deterministic lexical seed selection for a free-text query: lowercase
/// alphanumeric tokens (length >= 3, fixed stopword list) score every
/// non-reserved concept +3 per distinct token in the title, +2 in the
/// description or tags (JSON text), +1 in the body.
pub fn seeds(ing: &Ingested, query: &str, k: usize) -> Vec<Seed> {
    let q = query.to_lowercase();
    let toks: BTreeSet<String> = re_token()
        .find_iter(&q)
        .map(|m| m.as_str().to_string())
        .filter(|t| t.len() >= 3 && !OKF_STOPWORDS.contains(&t.as_str()))
        .collect();
    let mut out: Vec<Seed> = Vec::new();
    for c in ing.bundle.concepts.iter().filter(|c| !c.reserved) {
        let ttl = c.title.as_deref().unwrap_or("").to_lowercase();
        let dsc = c.description.as_deref().unwrap_or("").to_lowercase();
        let tgs = c
            .tags
            .as_ref()
            .map(|t| serde_json::to_string(t).unwrap_or_default())
            .unwrap_or_default()
            .to_lowercase();
        let bod = c.body.to_lowercase();
        let mut sc = 0_i64;
        for t in &toks {
            if ttl.contains(t.as_str()) {
                sc += 3;
            }
            if dsc.contains(t.as_str()) || tgs.contains(t.as_str()) {
                sc += 2;
            }
            if bod.contains(t.as_str()) {
                sc += 1;
            }
        }
        if sc > 0 {
            out.push(Seed {
                path: c.path.clone(),
                score: sc as f64,
                title: c.title.clone(),
            });
        }
    }
    out.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap()
            .then_with(|| a.path.cmp(&b.path))
    });
    out.truncate(k);
    out
}

#[derive(Debug, Clone)]
pub struct PprOptions {
    pub damping: f64,
    pub tol: f64,
    pub max_iter: usize,
    /// `None` = return all positive-score rows.
    pub k: Option<usize>,
    pub weights: Option<Vec<f64>>,
}

impl Default for PprOptions {
    fn default() -> Self {
        PprOptions {
            damping: 0.85,
            tol: 1e-12,
            max_iter: 200,
            k: Some(20),
            weights: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RankRow {
    pub path: String,
    pub score: f64,
    pub title: Option<String>,
    pub reserved: bool,
}

/// Round to `digits` decimal places with round-half-even on the decimal
/// representation — identical semantics to Python `round(x, digits)`.
pub fn round_dec(x: f64, digits: usize) -> f64 {
    format!("{x:.digits$}").parse().unwrap_or(x)
}

/// Personalized PageRank over the undirected resolved-link graph, seeded at
/// `starts` (teleport probability `1 - damping`, dangling mass returns to the
/// seed distribution). Deterministic: same bundle + starts always yields the
/// same scores, bit-identical to the R and Python bindings.
pub fn ppr(ing: &Ingested, starts: &[&str], opts: &PprOptions) -> Result<Vec<RankRow>, OkfError> {
    let concepts = &ing.bundle.concepts; // already sorted by path
    let nodes: Vec<&str> = concepts.iter().map(|c| c.path.as_str()).collect();
    let idx: HashMap<&str, usize> = nodes.iter().enumerate().map(|(i, p)| (*p, i)).collect();

    let missing: Vec<&str> = starts
        .iter()
        .copied()
        .filter(|s| !idx.contains_key(s))
        .collect();
    if !missing.is_empty() {
        return Err(OkfError::msg(format!(
            "start concept not found: {}",
            missing.join(", ")
        )));
    }
    let weights = match &opts.weights {
        Some(w) => w.clone(),
        None => vec![1.0; starts.len()],
    };
    if weights.len() != starts.len()
        || weights.iter().any(|w| *w < 0.0)
        || weights.iter().sum::<f64>() <= 0.0
    {
        return Err(OkfError::msg(
            "weights must be non-negative, same length as start, positive sum",
        ));
    }

    let n = nodes.len();
    // Distinct resolved links -> undirected edge set in sorted (s, d) order.
    let mut edges: BTreeSet<(usize, usize)> = BTreeSet::new();
    let distinct: BTreeSet<(&str, &str)> = ing
        .links
        .iter()
        .filter(|l| l.resolved)
        .map(|l| (l.src_path.as_str(), l.dst_path.as_deref().unwrap_or("")))
        .collect();
    for (s, d) in distinct {
        if s != d {
            if let (Some(&si), Some(&di)) = (idx.get(s), idx.get(d)) {
                edges.insert((si, di));
                edges.insert((di, si));
            }
        }
    }
    let mut deg = vec![0_usize; n];
    for (s_i, _) in &edges {
        deg[*s_i] += 1;
    }

    let mut seed = vec![0.0_f64; n];
    for (st, w) in starts.iter().zip(weights.iter()) {
        seed[idx[st]] += *w;
    }
    let tot: f64 = seed.iter().sum();
    for x in seed.iter_mut() {
        *x /= tot;
    }

    let mut p = seed.clone();
    for _ in 0..opts.max_iter {
        let mut contrib = vec![0.0_f64; n];
        for (s_i, d_i) in &edges {
            // fixed order -> deterministic fp
            if p[*s_i] != 0.0 {
                contrib[*d_i] += p[*s_i] / deg[*s_i] as f64;
            }
        }
        let mut dangling = 0.0_f64;
        for i in 0..n {
            if deg[i] == 0 {
                dangling += p[i];
            }
        }
        let mut np = vec![0.0_f64; n];
        for i in 0..n {
            np[i] =
                (1.0 - opts.damping) * seed[i] + opts.damping * (contrib[i] + dangling * seed[i]);
        }
        let mut delta = 0.0_f64;
        for i in 0..n {
            delta += (np[i] - p[i]).abs();
        }
        p = np;
        if delta < opts.tol {
            break;
        }
    }

    let mut rows: Vec<RankRow> = (0..n)
        .filter_map(|i| {
            let score = round_dec(p[i], 10);
            (score > 0.0).then(|| RankRow {
                path: nodes[i].to_string(),
                score,
                title: concepts[i].title.clone(),
                reserved: concepts[i].reserved,
            })
        })
        .collect();
    rows.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap()
            .then_with(|| a.path.cmp(&b.path))
    });
    if let Some(k) = opts.k {
        rows.truncate(k);
    }
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_dec_matches_python_round() {
        assert_eq!(round_dec(0.377590494_f64, 8), 0.37759049);
        assert_eq!(round_dec(0.125, 2), 0.12); // ties-to-even
        assert_eq!(round_dec(0.135, 2), 0.14); // 0.135 stored as 0.1350000000000000088818
        assert_eq!(round_dec(1.0, 10), 1.0);
    }

    #[test]
    fn stopwords_match_reference_count() {
        assert_eq!(OKF_STOPWORDS.len(), 37);
    }
}
