## Update: 0.5.2 -> 0.7.0

This is the first update after the initial CRAN acceptance (0.5.2). The gap
reflects development that completed while 0.5.2 was in the submission queue:

* 0.6.0 — `[[wikilink]]` reference resolution (id/alias/title/stem), so
  Obsidian-style vaults are ingestible; new `okf_extract_wikilinks()`.
* 0.7.0 — `okf_diff()`, a deterministic concept-level changelog between two
  bundle states (drift vs an ingested catalog, or snapshot vs snapshot).

No API changes or removals; both releases are additive. See NEWS.md.

## R CMD check results

0 errors | 0 warnings | 1 note

* The only NOTE is "Days since last update" — explained above (features were
  finished during the initial submission's review window).

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
