# okf (development version)

* New Rust binding (`rust/okf-ingest`, crates.io `okf-ingest`): the
  fixture-locked core — parse + `content_hash`, links/wikilinks, validate,
  ingest summary, exact PPR + lexical seeds + query cascade, diff (incl. drift
  mode), fetch (dir/tar/zip/git) — as a pure-Rust crate, conformance-gated in
  CI alongside R and Python (`conformance/check_rust.sh`). Catalog-free by
  design: every conformance-asserted value is computed in memory, which also
  documents that DuckDB is an access mechanism of the R/Python checkers, not
  part of the behavioral contract. No html/doctor/RAG/CLI in Rust.
* New C++ binding (`cpp/`, C++17 static library, CMake + FetchContent:
  rapidyaml + nlohmann/json + vendored SHA-1): the same fixture-locked core,
  conformance-gated in CI (`conformance/check_cpp.sh`, ctest on ubuntu +
  windows/MSVC). Fetch is descoped to dir / local tar (system `tar`) / git;
  zip and remote archives stay R/Python-only. Float parity pinned by
  `-ffp-contract=off` / `/fp:precise`.
* New MATLAB binding (`matlab/+okf`, pure MATLAB, Octave-compatible, zero
  toolboxes): the same fixture-locked core, conformance-gated in CI on real
  MATLAB (`conformance/check_matlab.sh`, matlab-actions). Ships a verbatim
  YAML-subset parser and a pure-M SHA-1; PPR rounding uses sprintf-based
  half-even (MATLAB `round()` is half-away-from-zero). Fetch covers
  dir / tar / zip / git with a post-extraction containment check.

# okf 0.9.0

* Query-seeded retrieval: new `okf_seeds()` (deterministic lexical seed
  selection — +3 title / +2 description·tags / +1 body per query token, fixed
  stopword list) and multi-seed `okf_rank()` (`start` may be a vector, with
  `weights`). `okf_context(query = "...")` chains them: lexical seeds ->
  multi-seed Personalized PageRank -> relevance-filled context. Deterministic
  hybrid retrieval with no embeddings; CLI `context --query`.
* `okf_doctor()` gains `duplicate_identity` (the same normalized id/alias
  claimed by more than one concept — breaks by-name resolution) and
  `hub_concentration` (info severity: pages whose outbound links mostly point
  at high in-degree hubs). New `info` severity never affects the health score
  (`n_info` added).
* Protected pages: concepts with `reviewed: true` in frontmatter are never
  modified by `okf_doctor_fix()` — human-validated content stays put.
* New conformance fixture locks query seeding + multi-seed PPR across R and
  Python.

# okf 0.8.0

* New `okf_rank()`: Personalized PageRank relevance scores over the concept
  graph, seeded on a start concept — exact power iteration (deterministic, no
  sampling, no embeddings), undirected resolved-link graph, teleport and
  dangling mass returning to the seed. New CLI verb `rank`.
* `okf_context(rank = "ppr")`: budget-fill the context blob by PPR relevance
  instead of BFS discovery order, so hub-heavy bundles surface the pages that
  matter to the topic first. Default behavior unchanged (`rank = "bfs"`).
* Cross-language parity: a new conformance fixture locks R and Python PPR
  scores byte-identical (10 decimals).

# okf 0.7.0

* New `okf_diff()`: deterministic concept-level changelog between two states
  of a bundle. Each side can be a bundle directory, an `okf_read()` bundle, a
  DuckDB catalog path, or an open connection — so it covers both "what drifted
  since the last ingest" (catalog vs directory) and snapshot-vs-snapshot
  comparison. Reports concepts added/removed/changed (by `content_hash`),
  frontmatter `type`/`title` changes, and link-graph deltas (edges
  added/removed, links newly broken or fixed).
* CLI: new `diff` verb (`okf diff <a> <b> [--json]`), exit 0 when identical /
  1 when different, for use as a CI change gate.

# okf 0.6.0

* `[[wikilink]]` support: `[[target]]` / `[[target|display]]` references are
  resolved by name — `id`, then `aliases`, then `title`, then filename stem —
  making Obsidian/Logseq/Foam-style vaults ingestible. Ambiguous names resolve
  to nothing (deterministic) rather than guessing. Markdown `](path)` links
  are unchanged.
* New `okf_extract_wikilinks()`; `okf_links()` now returns both link kinds.

# okf 0.5.2

* First CRAN release. Read, validate, and load OKF bundles into a portable
  DuckDB catalog; concept graph (`okf_links()`, `okf_backlinks()`,
  `okf_impact()`, `okf_clusters()`); HTML rendering (`okf_html()`,
  `okf_graph_html()`, Mermaid export); index-first context assembly
  (`okf_context()`); health checks (`okf_doctor()`, `okf_doctor_fix()`);
  incremental re-ingest/re-embed; optional local-embedder semantic search
  (`okf_embed()`, `okf_rag()`).
