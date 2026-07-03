## Update: 0.7.0 -> 0.9.0

Second update; consolidates two additive releases (see NEWS.md):

* 0.8.0 — `okf_rank()`: Personalized PageRank relevance over the concept
  graph, computed by exact power iteration (deterministic); `okf_context()`
  gains `rank = "ppr"` for relevance-weighted context assembly.
* 0.9.0 — `okf_seeds()` + multi-seed ranking: `okf_context(query = ...)`
  serves free-text queries via deterministic lexical seeding; `okf_doctor()`
  gains duplicate-identity and (info-severity) hub-concentration checks;
  `reviewed: true` pages are protected from `okf_doctor_fix()`.

No API changes or removals; all additive and offline (no new dependencies).

## R CMD check results

0 errors | 0 warnings | 1 note

* The only NOTE is "Days since last update" — the releases are additive and
  were completed together; consolidated here into one submission.

## Test environments

- Windows 11, R 4.5.0 (local)
- GitHub Actions: ubuntu-latest, macos-latest, windows-latest (R release)

## Notes

* The package optionally talks to a local Ollama server for embeddings
  (`okf_ollama_embedder`/`okf_embed`/`okf_rag`) and can fetch remote bundles
  (git/tar/zip) in `okf_fetch`; none of this runs during checks, examples, or
  tests — all tests use a small inline bundle in `tempdir()` and no network.
* `commonmark` (HTML rendering) and `httr2` (embeddings) are Suggests, guarded
  with `requireNamespace()`.
* There are no reverse dependencies.
