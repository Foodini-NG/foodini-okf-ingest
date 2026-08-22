# AGENTS.md

Ground rules for agents working in this repository.

**Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first.** It is the single source of
truth for how changes are made here. This file exists so an agent finds it, and
records only what is specific to agents.

## What this repo is

A Foodini fork of [okf-ingest](https://github.com/travisjakel/okf-ingest) by
Travis Jakel, taken at `f3b58994` (0.11.0), Apache-2.0. Python-only. See
[`NOTICE`](NOTICE).

Start from [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — it is the module map,
and it is upstream's, so it is accurate about design intent. Do not write a
second one.

Module ownership, for scoping a change:

| Module | Owns |
| -- | -- |
| `src/okf/okf.py` | ingest, source resolution, validate, query, context, the catalog |
| `src/okf/graph.py` | the emitted viewer, `impact`, `backlinks`, `clusters`, `rank`/PPR, `seeds` |
| `src/okf/cli.py` | the 13 subcommands, flags, output formatting |
| `src/okf/html.py` | HTML rendering |
| `src/okf/doctor.py` | health score and findings |
| `src/okf/diff.py` | bundle-to-bundle changelog |
| `src/okf/rag.py` | chunking, the pluggable embedder, cosine search |

## Hard rules

1. **Never send anything upstream.** No PRs, no issues, no bug reports to
   `travisjakel/okf-ingest`. This fork diverges deliberately. The `upstream`
   remote is fetch-only and its push URL is disabled on purpose.
2. **Never put Foodini bundle content in this repo.** No internal repo names,
   identifiers, paths, or measurements taken from the private knowledge bundle.
   This repository is public. Reproductions are synthetic — use
   `conformance/bundles/` or build a fixture. gitleaks catches credentials; it
   cannot catch internal identifiers.
3. **`python conformance/check_py.py` must print PASS** before you open a pull
   request. If a change moves an asserted value, update
   `conformance/expected/*.json` deliberately and say why. Never to make a red
   build green.
4. **Add the Apache-2.0 section 4(b) notice** to any file you change that does
   not already carry one. This is a licence obligation.
5. **Stay deterministic.** No LLM or agent calls, no randomness, no wall-clock
   in the core. See `CONTRIBUTING.md` for why this one matters to us
   specifically.
6. **Do not create or reconfigure public repositories, change branch protection,
   or publish packages.** Those are outward-facing; a human decides. Work on a
   branch, open a pull request, write up the recommendation.
7. **`main` is protected** — one approving review from a code owner, and both
   CI checks green. You cannot merge your own work.

## Where the work is tracked

Linear, Agentic team, project *"okf-ingest fork: catalog, graph and query fixes
plus new capabilities"*. Every issue names its owning module. Read the issue
before changing code; the reasoning is there, not here.
