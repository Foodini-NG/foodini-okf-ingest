---
type: Reference
title: The DuckDB catalog
description: The portable, SQL-queryable catalog the tool writes — the interop contract, and how a catalog holding several bundles is read.
timestamp: 2026-08-23T00:00:00Z
tags: [duckdb, schema, catalog]
---

# The DuckDB catalog

Ingesting a bundle loads it into a portable DuckDB catalog: `okf_bundle`,
`okf_concept` (one row per file, keyed by `(bundle_id, path)`), `okf_link` (the
resolved/broken graph edges), `okf_validation` (findings), and `okf_chunk`
(optional embeddings + each concept's `content_hash`).

The schema *is* the interop contract — see [conformance & parity](conformance.md).
Query it with SQL, the bare `duckdb` CLI, R, or Python. It powers
[rendering](render.md), [semantic search](search.md), [incremental](incremental.md)
re-runs, and [doctor](doctor.md). The whole thing is [deterministic](determinism.md).

## One catalog, several bundles

Every table carries `bundle_id`, and `okf_concept` is keyed by `(bundle_id, path)`,
so a catalog can hold many bundles — [diff](diff.md) relies on exactly that.

**Reads are scoped to one bundle.** Pass `bundle_id=` in the library or `--bundle`
on the [CLI](cli.md). With a single-bundle catalog you can omit it and the only
bundle is used, which is the common case. With more than one and no choice given,
the read is **refused** and the candidate ids are listed.

Refusing is deliberate. Concept paths collide across bundles — `src/main.py`
exists in plenty of repositories — so an unscoped read spanning two bundles
returns a mixed result that looks entirely plausible and is wrong. An error you
can act on beats a confident wrong answer.
