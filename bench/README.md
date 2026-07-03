# Retrieval benchmark

`retrieval_bench.py` measures the retrieval stack on real OKF bundles along
three axes — **quality**, **cost**, and **run-to-run stability** — and
includes a **Monte-Carlo PPR baseline** (the sampled-PageRank approach used by
LLM-wiki tools) to quantify what exact power iteration buys.

## Protocol: leave-one-link-out (LOLO)

No labeling, no LLM judge, fully deterministic. For every evaluation page `p`
(non-reserved, ≥ 2 resolved outbound links): hide `p`'s outbound edges from
the graph, ask each method for the pages most related to `p`, and score the
ranking against the hidden link targets — the pages the author actually
connected. Metrics: Recall@k and MRR, averaged over eval pages. Reserved
pages (index/log) are excluded from candidates and ground truth.

## Methods

| Method | What it is |
|---|---|
| `bfs` | undirected neighbors of `p` (depth 1 then 2, discovery order) — okf_context's selection before 0.8.0 |
| `ppr` | exact power-iteration Personalized PageRank from `p` (okf 0.8.0) |
| `query-ppr` | okf 0.9.0 cascade with `p`'s title+description as a free-text query: lexical seeds → multi-seed exact PPR |
| `mc-ppr` | Monte-Carlo PPR: K random walks with restart, visit counts as scores — run under multiple RNG seeds to measure ranking churn |
| `embed` | (`--embed`, local Ollama nomic-embed-text) cosine similarity of page-body embeddings — the vector-search alternative |

Deterministic methods are executed twice per query and asserted identical
(`identical-reruns`). The bench's internal PPR is sanity-checked against
`okf.graph.ppr` (max score delta < 1e-9 on the conformance fixture).

## Run it

```bash
python bench/retrieval_bench.py <bundle> [...] [--k 5 10] [--embed] \
    [--max-pages 150] [--mc-walks 1000 10000] [--mc-runs 10] [--json out.json]
```

## Results

Run 2026-07-02 on three real corpora (private ops wiki, Molnar's
*Interpretable ML* as a bundle, OSQF conference-talk wiki). LOLO protocol,
Recall@5/@10 + MRR averaged over eval pages; `ms/q` = mean per-query cost.

**Ops wiki — 120 pages, 425 edges, hub-heavy living KB (58 eval pages):**

| method | R@5 | R@10 | MRR | ms/q | identical reruns |
|---|---|---|---|---|---|
| bfs | 0.290 | 0.370 | 0.585 | 0.0 | yes |
| ppr | 0.480 | 0.669 | 0.659 | 6.3 | yes |
| **query-ppr** | **0.538** | **0.744** | 0.763 | 19.0 | yes |
| embed (nomic, local) | 0.533 | 0.709 | **0.777** | 9.3 (+255s build) | yes |

**Interpretable-ML book — 69 pages, 278 edges, dense regular linking (64 eval):**

| method | R@5 | R@10 | MRR | ms/q | identical reruns |
|---|---|---|---|---|---|
| **bfs** | **0.857** | 0.897 | **0.970** | 0.0 | yes |
| ppr | 0.833 | **0.909** | 0.884 | 3.0 | yes |
| query-ppr | 0.312 | 0.574 | 0.294 | 5.1 | yes |
| embed | 0.422 | 0.741 | 0.375 | 5.3 | yes |

**OSQF talks — 1,302 pages, 3,481 edges, hub-and-spoke (100 eval):**

| method | R@5 | R@10 | MRR | ms/q | identical reruns |
|---|---|---|---|---|---|
| bfs | 0.322 | 0.322 | 0.573 | 0.0 | yes |
| ppr | **0.328** | **0.339** | **0.581** | 69.7 | yes |
| query-ppr | 0.170 | 0.223 | 0.258 | 116.0 | yes |

**Monte-Carlo PPR baseline** (10 seeds per query; top-5 Jaccard, 1.0 = identical):

| corpus | K walks | R@5 | run-to-run agreement | vs exact ranking |
|---|---|---|---|---|
| ops wiki | 1,000 | 0.494 | 0.801 | 0.846 |
| ops wiki | 10,000 | 0.490 | 0.928 | 0.955 |
| iml book | 1,000 | 0.646 | 0.764 | 0.815 |
| iml book | 10,000 | 0.642 | 0.875 | 0.892 |
| osqf | 1,000 | 0.283 | 0.878 | 0.903 |
| osqf | 10,000 | 0.283 | 0.919 | 0.934 |

### What the numbers say

1. **On the living, hub-heavy wiki — the case okf targets — query-seeded
   exact PPR nearly doubles BFS recall** (R@5 0.29 → 0.54, R@10 0.37 → 0.74)
   and **matches locally-embedded vector search** with no embedding
   infrastructure: 19ms per query vs a 255-second embedding build.
2. **Structure decides the winner.** On the densely, regularly linked book
   bundle, plain BFS is already near-optimal (0.857) — depth-1 *is* the
   author's answer there, and lexical/vector methods lag badly. Use
   `rank=ppr`/`query` on messy real-world wikis; BFS remains the right
   default on clean hierarchies.
3. **Sampled PPR is unstable by construction**: Monte-Carlo top-5 rankings
   change on 7–24% of slots between runs of the *same query on the same
   corpus* (and never reach the exact ranking), while exact power iteration
   is bit-identical every run at 3–70ms per query even on a 1,300-page
   graph. Sampling buys nothing at these scales.


## Reading the results

- **Exact PPR vs BFS** — the quality gap is what relevance-weighted selection
  buys over "everything at depth 1 is equal".
- **`identical-reruns: yes`** for every okf method — the determinism claim as
  an empirical column, not just a design statement.
- **mc-ppr churn** — `run-to-run top-k Jaccard < 1` means a sampled PPR
  returns *different top results on every run of the same query on the same
  corpus*; `vs exact` shows how far the samples sit from the true ranking.
  Exact power iteration costs milliseconds at these graph sizes and removes
  both problems.
- **embeddings** — a different modality (text similarity, not graph
  structure); useful as an honest alternative, and complementary rather than
  competing (okf's `embed`/`rag` layer remains available where it wins).

Caveats, honestly held: LOLO measures "retrieve what the author linked",
which favors graph methods on densely-linked bundles and text methods on
sparsely-linked ones; scores are relative to a bundle's linking discipline,
not absolute retrieval goodness; and the MC-PPR baseline is our faithful
reimplementation (visit-count random walks with restart), not any specific
product's code.
