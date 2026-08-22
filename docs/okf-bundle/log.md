---
type: Log
title: Change log
description: Chronological history of the okf-ingest self-bundle, including the Foodini fork.
timestamp: 2026-08-22T00:00:00Z
tags: [log]
---

# Change log

- **2026-06-23** Creation — okf-ingest documents itself as an OKF bundle
  (dogfood): determinism, the OKF format, catalog, conformance, bindings,
  sources, validate, the concept graph, query, context, cli, install, render,
  search, incremental, doctor. Rendered by `okf html`/`okf graph` (the README
  hero); gated by `okf doctor` (100/100) in CI.
- **2026-06-26** 0.7.0 — `okf diff`: deterministic concept-level changelog
  between two bundle states (drift vs catalog, or snapshot vs snapshot); new
  conformance fixture locks R/Python parity. Prompted by reviewing
  matrixorigin/Memoria's `memory_diff` — the one idea there with a clean
  file-native analog.
- **2026-07-02** 0.8.0 — `okf rank`: exact power-iteration Personalized
  PageRank over the concept graph (deterministic, parity-locked); `context
  --rank ppr` budget-fills by relevance. Idea credit: the Obsidian Karpathy
  LLM Wiki plugin's Monte-Carlo PPR retrieval — made exact here.
- **2026-07-02** 0.9.0 — query-seeded retrieval (`context --query`: lexical
  seeds -> multi-seed exact PPR; deterministic hybrid retrieval, no
  embeddings); doctor gains `duplicate_identity` + info-level
  `hub_concentration`; `reviewed: true` pages are protected from `--fix`.
- **2026-08-22** Foodini fork — forked at `f3b58994` (0.11.0). Reduced to the
  Python binding alone: the R, Rust, C++ and MATLAB bindings and their
  conformance checkers are removed, as is the original author's `blog/`. The
  binding moves `py/okf` -> `src/okf`, the distribution becomes
  `foodini-okf-ingest` and the command becomes `okf-ingest` (the bare `okf`
  collided with okf-generator). Python floor raised to 3.14, uv-managed. The
  catalog `schema/` and the `conformance/` corpus are kept unchanged and remain
  the regression gate. Rationale and licence notices: see `NOTICE` and
  `CONTRIBUTING.md` at the repo root.
- **2026-08-23** `validate` gains `--summary` and severity / rule / path filters.
  A bundle mixing hand-written and generated concepts produces warnings that are
  overwhelmingly expected, and the flat list had no usable signal — 23,723
  warnings in the case that prompted this, all of them in the generated layer.
  Path patterns are globs, except that a pattern with no wildcard is a prefix.
  Filters change what is *reported*, never what conformance is judged on:
  `conformant` and the error count are always computed over every finding, and a
  filtered run states how many it suppressed.
- **2026-08-23** Catalog reads are scoped to one bundle. The schema was always
  multi-bundle (`okf_concept` is keyed by `(bundle_id, path)`) but 28 of 31 reads
  omitted the predicate, so any catalog holding two bundles silently mixed them —
  and since concept paths collide across bundles, the mixed answer looked
  plausible. `resolve_bundle` now decides: explicit `bundle_id` wins, otherwise
  the single bundle, otherwise the read is refused with the candidates named.
  `--bundle` on every subcommand that reads a catalog. Two `okf_chunk` DELETEs in
  the embed path were also unscoped, so re-embedding one bundle could delete
  another's rows — destructive, not merely wrong. Guarded two ways: a `twobundles`
  conformance fixture with a colliding path, and a static check
  (`conformance/check_scoping.py`) that fails on any unscoped statement without a
  stated exception.
