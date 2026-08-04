# Architecture

## The decision: "core + bindings" as a *contract*, not a binary

A literal core+bindings design (Rust/C core, `extendr`/`pyo3` bindings) was
rejected. For an OKF ingestion tool it's the wrong trade: parsing markdown+YAML
and loading a DB is light glue, an R-native maintainer shouldn't carry a Rust
toolchain, and a heavy required binary contradicts OKF's "no required tooling"
ethos.

Instead the **core is two portable, language-neutral artifacts**, and the
**bindings are thin native packages** held to the core by tests:

| Layer | Artifact | Role |
|-------|----------|------|
| Core  | `schema/catalog.sql` | The DuckDB catalog schema — the interop contract. Both bindings emit identical catalogs; queryable with the bare `duckdb` CLI. |
| Core  | `conformance/` | Golden bundles + `expected/*.json`. The behavioral contract every binding reproduces. |
| Binding | `r/okf/` | R: yaml, DBI, duckdb, digest, jsonlite. Full surface. |
| Binding | `py/okf/` | Python: pyyaml, duckdb (stdlib hashlib/json). Full surface. |
| Binding | `rust/okf-ingest/` | Rust: yaml-rust2, sha1, regex, serde_json, tar/flate2/zip. Fixture-locked core only, catalog-free. |
| Binding | `cpp/` | C++17: rapidyaml, nlohmann/json, vendored SHA-1; system `tar`/`git` for fetch. Fixture-locked core only, catalog-free. |
| Binding | `matlab/+okf/` | Pure MATLAB (Octave-compatible, zero toolboxes): minimal YAML-subset parser, pure-M SHA-1, jsonencode, untar/unzip builtins. Fixture-locked core only, catalog-free. |

A new binding (TS, Go, …) is conformant the moment it passes `conformance/`.
The Rust binding demonstrates that the catalog itself is not part of the
behavioral contract: every conformance-asserted value (summary fields, content
hashes, findings, link resolutions, PPR scores, diff deltas) is derivable from
the in-memory ingest result — DuckDB is the R/Python checkers' *access
mechanism*, not the contract. A binding that skips the catalog is still fully
conformant on the core.

## Data flow (identical in both bindings)

```
bundle dir ─▶ read ─▶ parse frontmatter (YAML)         ─┐
                      extract markdown links            │
                      resolve links (abs / rel / extern)│
              ─▶ validate (OKF §6 hard rules + soft)    ├─▶ DuckDB catalog
              ─▶ ingest:  okf_bundle / okf_concept /     │   (okf_*) ─▶ query / RAG
                          okf_link / okf_validation     ─┘            ─▶ context (LLM blob)
                                                                      ─▶ html (render for viewing)
```

## Consume layers (all read the same catalog)

The catalog has three consume paths, each a thin reader over the `okf_*` tables —
none re-parses the bundle:

| Layer | Function | Reads | Output |
|-------|----------|-------|--------|
| Semantic | `okf_rag` / `rag` | `okf_chunk` (embeddings) | top-k chunks |
| Context | `okf_context` / `context` | `okf_concept` + `okf_link` | index-first markdown blob for an LLM |
| Render | `okf_html` / `render_html` | `okf_concept` + `okf_validation` + `okf_link` | static HTML (site or single file) |
| Graph | `okf_graph_html` / `okf_graph_json` / `okf_backlinks` / `okf_impact` / `okf_clusters` | `okf_concept` + `okf_link` | force-directed page · `{nodes,edges}` JSON · backlinks · ripple · communities |

All **deterministic** — no LLM, no model calls. Community detection is
synchronous label propagation with lexicographic tie-breaking (reproducible);
the graph page colours by OKF `type` with community as the fallback. This is the
deliberate line vs. LLM-agent "understand my wiki" tools: okf surfaces the graph
the human authored and hands it to *your* LLM via `context`/`rag` — it does not
generate summaries, entities, or claims itself.

**Incremental.** `okf_chunk` carries each concept's `content_hash`, and
`okf_concept` rows are keyed by `(bundle_id, path)`. `ingest --incremental` and
`embed --incremental` diff those hashes against the prior catalog and touch only
what changed; links and validation are always recomputed (cheap, graph-global).
A full `ingest` is an idempotent replace of the bundle's rows.

**Rank.** `okf_rank` / `ppr` is exact power-iteration Personalized PageRank
over the undirected resolved-link graph (teleport + dangling mass to the
seed) — deterministic where the usual Monte-Carlo PPR is not, and parity-locked
across bindings by a conformance fixture (scores to 10 decimals; Python
iterates edges in sorted order so floating-point accumulation matches R's
grouped sums). `context(rank = "ppr")` consumes it for relevance-weighted
budget-filling. Free-text queries chain `okf_seeds` (deterministic lexical
scoring: +3 title / +2 description-or-tags / +1 body per token, fixed
stopword list mirrored across bindings) into multi-seed PPR -- the full
lexical -> seeds -> walk cascade with no embeddings. Doctor findings carry a
third `info` severity (e.g. `hub_concentration`) that reports without
affecting the health score; `reviewed: true` pages are exempt from
`doctor --fix`.

**Diff.** `okf_diff` / `diff` reuses the same `content_hash` for a
*user-facing* changelog between any two bundle states (each side a directory,
an `okf_read()` bundle, a `.duckdb` path, or an open connection): concepts
added/removed/changed, `type`/`title` frontmatter changes, and edge/broken-link
deltas. Pure hash/set comparison sorted by path — catalog-vs-dir is drift since
last ingest; dir-vs-dir is a snapshot changelog. A dedicated conformance
fixture (`bundles/diff_a` / `diff_b`) locks both bindings to the same output.

`okf_html` is deliberately the thinnest of the three: it rewrites internal `.md`
links to page-relative `.html` (site) or `#anchors` (single), wraps each concept
in a metadata bar + validation-derived footer badge, and inlines one CSS string
(mirrored across bindings like `OKF_SCHEMA`). No JS, no build step — the only new
dependency is a markdown engine, optional and guarded (`commonmark` Suggests in
R; the `okf-ingest[html]` extra in Python). Link resolution reuses
`okf_resolve_link`, so the rendered graph matches the validated graph exactly.

## Parity notes (where the languages had to be aligned)

- **Timestamps**: PyYAML coerces ISO datetimes to `datetime`; R keeps them as
  strings. The Python loader (`_OKFLoader`) drops the timestamp implicit
  resolver so both keep the authored string verbatim (and frontmatter stays
  JSON-serializable).
- **Content hash**: `sha1` of the body in both — R uses
  `digest(..., serialize = FALSE)`; Python uses `hashlib.sha1`. The body is
  normalized identically (Python's `splitlines()` matches R's `readLines()`:
  both strip the trailing newline and CR in CRLF), so `content_hash` matches
  across bindings. A conformance test (`content_hashes` in `expected/store.json`)
  locks this so it cannot regress.
- **`frontmatter` JSON** is semantically equal but **not** byte-identical across
  languages (key ordering/spacing differ); conformance asserts on parsed
  structure, not raw JSON bytes. So catalogs match on every column except the
  raw `frontmatter` text.
- **`n_concepts`** counts non-reserved concept documents; `index.md`/`log.md`
  are catalogued (`reserved = true`) but not counted as concepts (OKF: "all
  other `.md` files are concept documents").
- **MATLAB specifics**: no YAML library exists that keeps timestamps verbatim
  (yamlmatlab coerces dates — exactly the forbidden behavior), so the binding
  ships a ~150-line YAML-subset parser (`okf.yaml_parse`): flat `key: value`,
  quoted strings, flow/block sequences, everything verbatim text;
  out-of-subset constructs raise the spec-sanctioned `yaml_parse_error`.
  MATLAB `round()` is round-half-AWAY-from-zero — `okf.round_dec`
  (`sprintf('%.*f')` + `str2double`) provides the half-even rounding the PPR
  score lock requires. SHA-1 is a pure-M implementation (no Java — future
  MATLAB releases drop the JVM). Sorting/tie-breaks use explicit two-key
  `sortrows` (never relying on sort stability). Archive fetch extracts into a
  fresh temp dir and containment-checks every returned path afterwards
  (untar/unzip cannot list members pre-extraction; MATLAB returns absolute
  paths, Octave member-relative — both handled). The code stays inside the
  MATLAB/Octave-common subset and CI runs real MATLAB.
- **C++ specifics**: rapidyaml keeps every scalar as raw text (no implicit
  typing), so verbatim timestamps and `"0.1"` come free; frontmatter scalars
  land in JSON as strings (semantically equal, not byte-locked). PPR parity
  requires the build to never enable fast-math or FMA contraction — CMake
  pins `-ffp-contract=off` (GCC/Clang) and `/fp:precise` (MSVC); `round_dec`
  is `snprintf("%.Nf")` + `strtod` (correctly-rounded on glibc and UCRT).
  Fetch shells out to the system `tar` with fully RELATIVE paths: GNU tar
  reads drive-colon `-f` args as remote `host:path` syntax and msys tar
  mishandles drive-colon `-C` targets, so the archive is copied next to the
  extraction dir first. zip and remote-archive fetch are not supported (use
  R/Python).
- **Rust specifics**: yaml-rust2 speaks YAML 1.2 core schema — there is no
  timestamp tag, so verbatim timestamps come free (no custom loader needed);
  float scalars keep their raw text. Known unlocked divergences (documented,
  not chased; no fixture covers them): unquoted `yes`/`no`/`on`/`off` are bools
  in PyYAML (1.1) but strings in 1.2, and boolean scalars stringify as
  `True`/`true`/`TRUE` across Python/Rust/R. PPR uses `f64` with the same
  sorted-edge accumulation order as Python and decimal round-half-even via
  fixed-precision formatting, so scores are bit-identical. Concepts sort by
  *relative* forward-slash path in byte order (Python sorts absolute paths —
  equivalent on the fixtures, and the relative sort is the safer invariant on
  Windows).

## Roadmap

- ~~`okf_chunk` embeddings + vector search~~ — shipped (`embed` / `rag`).
- ~~An `okf` CLI in both languages~~ — shipped (`validate`/`ingest`/`query`/`context`/`html`/`embed`/`rag`).
- ~~git / tar / zip bundle readers~~ — shipped (`okf_fetch`).
- ~~Interactive graph view + community clustering + backlinks + incremental~~ —
  shipped (`graph`/`export`/`impact`, `okf_clusters`, `--incremental`).
- HTML render polish: optional sidebar nav, theme palettes (the `html` page
  itself stays minimal: no JS, inline CSS).
