# okf-ingest (Rust)

Open Knowledge Format (OKF) ingestion — the Rust binding of
[okf-ingest](https://github.com/travisjakel/okf-ingest), covering the
**fixture-locked core**: frontmatter parsing + body normalization
(`content_hash`), markdown-link and `[[wikilink]]` extraction/resolution, OKF
validation, ingest summaries, exact Personalized-PageRank ranking
(deterministic, no sampling), lexical query seeding, concept-level diff, and
bundle fetch (dir / tar / zip / git).

Byte-identical with the R and Python bindings on the shared conformance
fixtures — PPR scores match to 10 decimals, content hashes exactly.

```rust
use okf_ingest::{ingest, ppr, seeds, PprOptions};

let ing = ingest("path/to/bundle")?;
assert!(ing.summary.conformant);
let ranked = ppr(&ing, &["index.md"], &PprOptions::default())?;
let hits = seeds(&ing, "how is revenue computed?", 5);
```

Out of scope by design (use the R or Python binding): HTML render, doctor,
graph exports, RAG/embeddings, CLI, DuckDB catalog — every
conformance-asserted value is available on the in-memory `Ingested` struct.

Full documentation, the OKF spec notes, and the conformance protocol live in
the [repository README](https://github.com/travisjakel/okf-ingest).
