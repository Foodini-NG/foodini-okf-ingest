# Contributing to foodini-okf-ingest

> **Rewritten by Foodini 2026-08-22.** This replaces the original work's
> CONTRIBUTING.md, whose rules were built around holding five language bindings
> in lockstep. Derived from okf-ingest by Travis Jakel (Apache-2.0) — see
> `NOTICE`.

**Contributions here are welcome** — open an issue or a pull request. This is a
fork maintained for Foodini's own use, so changes are judged partly on whether
they serve that purpose, but a good fix is a good fix and we would rather have it.

## Consider contributing to the original instead — it is probably the better home

If your change is **generally useful rather than Foodini-specific**, please take
it to [**travisjakel/okf-ingest**](https://github.com/travisjakel/okf-ingest)
first. It is the better place for it, for concrete reasons:

* **Five bindings, not one.** R, Python, Rust, C++ and MATLAB, held
  byte-identical by the shared conformance corpus. A fix landed there reaches
  every one of them; the same fix landed here reaches Python on Foodini's
  machines. That is a large difference in who benefits.
* **It is actively developed.** Six releases in six weeks over 2026-06/08, plus
  CRAN and conda-forge packaging. Not a dormant project.
* **It is the real project.** This fork exists because Foodini did not want to
  maintain four bindings it does not write — not because of any disagreement with
  the original's design. Upstream has the wider audience, the maintainer who
  knows the code best, and the packaging to distribute a fix properly.
* **Its `CONTRIBUTING.md` sets a clear bar** — deterministic core, the
  conformance contract, both R and Python moved together. Worth reading; the
  design line is a good one and we kept it here.

So: a bug in OKF parsing, link resolution, PPR, diff, doctor or rendering almost
certainly belongs upstream. Something that only matters because of how Foodini
runs this — our packaging, our Python floor, our pipeline integration — belongs
here.

If you are unsure, open an issue here and we will say which we think it is. And
if a change lands upstream that we are carrying separately, tell us: we would
rather drop our version and take theirs.

**One thing we ask.** Do not carry *this fork's* divergences upstream, and do not
report bugs upstream that are ours rather than theirs — the renamed command, the
3.14 floor, the removed bindings, our packaging. Travis Jakel did not make those
choices and should not field questions about them.

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

That has a consequence worth stating plainly: **a feature designed as generic
capability is, almost by definition, one that belongs upstream.** If you find
yourself building something genuinely general, propose it at
[travisjakel/okf-ingest](https://github.com/travisjakel/okf-ingest) — its
`CONTRIBUTING.md` asks for an issue before a large feature — and let it reach
five bindings instead of one. Build it here when upstream declines it, when we
need it sooner than that conversation can run, or when it is only meaningful
inside Foodini's pipeline.

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
