---
type: Log
title: Change log
description: Chronological history of the okf-ingest self-bundle.
timestamp: 2026-06-23T00:00:00Z
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
