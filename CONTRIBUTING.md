# Contributing to foodini-okf-ingest

> **Rewritten by Foodini 2026-08-22.** This replaces the original work's
> CONTRIBUTING.md, whose rules were built around holding five language bindings
> in lockstep and around contributing to `travisjakel/okf-ingest`. Neither
> applies here. Derived from okf-ingest by Travis Jakel (Apache-2.0) — see
> `NOTICE`.

This is a **fork maintained for Foodini's own use**, not a community project.
Changes are welcome, but they are judged on whether they serve Foodini's
knowledge pipeline. If you want the general-purpose, multi-language tool, use
[the original](https://github.com/travisjakel/okf-ingest) — it is actively
developed and it is the better choice.

**Do not send our changes upstream, and do not report our bugs upstream.** This
fork diverges deliberately.

## The one rule: stay deterministic

Same bundle in, same catalog / graph / clusters / render out. No LLM or agent
calls anywhere in the core. No randomness (`random`/`uuid`/`sample`/`shuffle`),
no wall-clock except the overridable `ingested_at`. If a feature needs a model to
decide something, it belongs in a *caller* — hand it the graph via
`okf-ingest context` — not in here.

This is inherited from the original work, and we keep it for our own reasons: the
QM documentation pipeline regenerates unconditionally on every refresh and
assumes that unchanged input yields unchanged output. `rank`'s whole advantage
over the usual Monte-Carlo Personalized PageRank is that it is exact and
reproducible. Determinism is the property that makes both true.

*(Formally still a pending decision on the QM side — see the determinism-line
entry in `00-qm-decisions.md`. Treat it as binding until that says otherwise.)*

## The gate: `conformance/`

```bash
python conformance/check_py.py      # must print PASS
```

Stdlib-only, standalone, and run by CI on every push and pull request.

`conformance/` is golden bundles plus `expected/*.json`. In the original it
proved that five independent implementations produced byte-identical output.
Here there is one implementation, so it is a **behavioural regression gate** —
and a strict one, precisely because every value it pins had to be reproducible in
five languages.

If your change moves a conformance-asserted value — summary fields, content
hashes, findings, link resolutions, PPR scores, diff deltas — update the expected
JSON **deliberately** and say why in the pull request. Never update it to make a
red build go green.

When you fix a bug that the corpus did not catch, add or extend a fixture so it
cannot come back.

## Working on a change

1. Branch. `main` is protected: no direct pushes, one review required.
2. **One pull request, one problem.** Smallest diff that fixes it and proves it.
3. **Every change carries a test** that fails before and passes after.
4. Add the Apache-2.0 section 4(b) notice to any file you change that does not
   already carry one:
   ```
   Modified by Foodini <YYYY-MM-DD>: <what changed>. Derived from okf-ingest by
   Travis Jakel (Apache-2.0) — see NOTICE.
   ```
   This is a licence obligation, not a formality. One notice per file is enough;
   extend the existing one rather than stacking them.
5. Keep `docs/ARCHITECTURE.md`'s **Parity notes** in mind before simplifying
   anything. They document why the timestamp resolver, body normalisation,
   sorted-edge PPR accumulation and reserved-document counting look odd. Those
   are load-bearing.
6. Update `docs/okf-bundle/` if you change behaviour it describes, and add a line
   to `docs/okf-bundle/log.md`.

## Never in this repo

**No Foodini bundle content, repo names, identifiers, paths or measurements
taken from the private knowledge bundle.** This repository is public.
Reproductions are synthetic — use `conformance/bundles/` or build a fixture.

`gitleaks` enforces the credential half of this on every push and via a
pre-commit hook (`pre-commit install` — it is per-clone opt-in, which is why the
CI gate also exists). It cannot enforce the "no internal identifiers" half. That
one is on you.

## Dogfood

The project documents itself as an OKF bundle in
[`docs/okf-bundle/`](docs/okf-bundle/). `okf-ingest validate docs/okf-bundle
--strict` and `okf-ingest doctor docs/okf-bundle --strict` must stay clean
(0 warnings, 100/100). CI checks both. If your change touches behaviour
described there, update the bundle too.

## Scope

**Consume-first**: validate / load / query / render / graph / search / maintain.
Authoring is out of scope, as it was upstream.

Features are permitted here — unlike in the okf-generator fork — but design them
as generic capability rather than a Foodini special case wherever that is the
better design. It usually is, and it keeps the code explicable to the next
person.

## Setup

Python 3.14+, uv-managed:

```bash
uv venv --python 3.14
uv pip install -e ".[html]"
pre-commit install
python conformance/check_py.py
```

Dependency versions are constrained by `[tool.uv] exclude-newer` in
`pyproject.toml`, which enforces Foodini's "no library newer than two weeks"
rule across all transitive dependencies. Bump that date to
`(re-lock date - 14 days)` whenever you re-lock.
