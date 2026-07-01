"""okf — diff: a DETERMINISTIC concept-level changelog between two states of a
knowledge base.

`git diff` shows text hunks; `diff()` shows what changed as *knowledge
structure*: concepts added/removed, bodies changed (by content_hash),
frontmatter type/title changes, and graph deltas (edges added/removed, links
newly broken / fixed). Each side can be a bundle directory, a Bundle from
read_bundle(), a .duckdb catalog path, or an open duckdb connection — so
`diff(catalog, dir)` answers "what drifted since the last ingest" and
`diff(old_dir, new_dir)` compares two snapshots. Pure hash/set comparison,
outputs sorted by path: no model, no wall clock.

Mirrors r/okf/R/okf_diff.R.
"""
from __future__ import annotations
import os
from typing import Any, Optional

import duckdb

from .okf import Bundle, read_bundle, links as _links


def _state_from_con(con, bundle_id: Optional[str] = None) -> dict:
    if bundle_id is None:
        bids = [r[0] for r in con.execute(
            "SELECT DISTINCT bundle_id FROM okf_concept").fetchall()]
        if len(bids) > 1:
            raise ValueError("catalog contains multiple bundles; pass a bundle_id")
        if not bids:
            raise ValueError("catalog contains no ingested bundle")
        bundle_id = bids[0]
    cps = {p: {"type": t, "title": ti, "content_hash": h} for p, t, ti, h in con.execute(
        "SELECT path, type, title, content_hash FROM okf_concept WHERE bundle_id = ?",
        [bundle_id]).fetchall()}
    lks = con.execute(
        "SELECT src_path, dst_raw, dst_path, resolved FROM okf_link WHERE bundle_id = ?",
        [bundle_id]).fetchall()
    edges = {(s, dp) for s, _, dp, res in lks if res}
    broken = {(s, dr) for s, dr, _, res in lks if not res}
    return {"concepts": cps, "edges": edges, "broken": broken}


def bundle_state(x: Any, bundle_id: Optional[str] = None) -> dict:
    """Normalize one diff side (dir / Bundle / .duckdb path / connection) to a
    comparable state: concepts {path -> type/title/content_hash}, resolved edge
    set, and broken-link set."""
    if isinstance(x, duckdb.DuckDBPyConnection):
        return _state_from_con(x, bundle_id)
    if isinstance(x, str) and x.endswith(".duckdb") and os.path.isfile(x):
        con = duckdb.connect(x, read_only=True)
        try:
            return _state_from_con(con, bundle_id)
        finally:
            con.close()
    if isinstance(x, Bundle):
        b = x
    elif isinstance(x, str) and os.path.isdir(x):
        b = read_bundle(x)
    else:
        raise ValueError(
            "diff side must be a bundle dir, read_bundle() Bundle, .duckdb path, or connection")
    cps = {c.path: {"type": c.type, "title": c.title, "content_hash": c.content_hash}
           for c in b.concepts}
    lk = _links(b)
    edges = {(l["src_path"], l["dst_path"]) for l in lk if l["resolved"]}
    broken = {(l["src_path"], l["dst_raw"]) for l in lk if not l["resolved"]}
    return {"concepts": cps, "edges": edges, "broken": broken}


def _field_diff(common, ca, cb, field):
    out = []
    for p in sorted(common):
        x, y = ca[p][field], cb[p][field]
        if x != y:
            out.append({"path": p, "from": x, "to": y})
    return out


def _pair_diff(a: set, b: set, cols) -> list:
    return [dict(zip(cols, pair)) for pair in sorted(a - b)]


def diff(a: Any, b: Any, bundle_id_a: Optional[str] = None,
         bundle_id_b: Optional[str] = None) -> dict:
    """Concept-level diff between two states of an OKF knowledge base.

    Reports concepts added / removed / changed (by body content_hash),
    frontmatter type/title changes, and concept-graph deltas (edges added/
    removed, links newly broken or fixed). Fully deterministic: pure hash and
    set comparison, all output sorted, no wall clock.
    """
    sa = bundle_state(a, bundle_id_a)
    sb = bundle_state(b, bundle_id_b)
    ca, cb = sa["concepts"], sb["concepts"]

    added = sorted(set(cb) - set(ca))
    removed = sorted(set(ca) - set(cb))
    common = set(ca) & set(cb)
    changed = sorted(p for p in common if ca[p]["content_hash"] != cb[p]["content_hash"])

    type_changed = _field_diff(common, ca, cb, "type")
    retitled = _field_diff(common, ca, cb, "title")

    links_added = _pair_diff(sb["edges"], sa["edges"], ("src_path", "dst_path"))
    links_removed = _pair_diff(sa["edges"], sb["edges"], ("src_path", "dst_path"))
    broken_added = _pair_diff(sb["broken"], sa["broken"], ("src_path", "dst_raw"))
    broken_fixed = _pair_diff(sa["broken"], sb["broken"], ("src_path", "dst_raw"))

    identical = not (added or removed or changed or type_changed or retitled or
                     links_added or links_removed or broken_added or broken_fixed)

    return {
        "identical": identical, "added": added, "removed": removed, "changed": changed,
        "type_changed": type_changed, "retitled": retitled,
        "links_added": links_added, "links_removed": links_removed,
        "broken_added": broken_added, "broken_fixed": broken_fixed,
        "summary": {
            "added": len(added), "removed": len(removed), "changed": len(changed),
            "unchanged": len(common) - len(changed),
            "type_changed": len(type_changed), "retitled": len(retitled),
            "links_added": len(links_added), "links_removed": len(links_removed),
            "broken_added": len(broken_added), "broken_fixed": len(broken_fixed)},
    }
