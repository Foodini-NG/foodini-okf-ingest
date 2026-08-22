---
type: Concept
title: The Python binding
description: One thin, native Python package, with the conformance corpus retained as its regression gate.
timestamp: 2026-08-22T00:00:00Z
tags: [python, bindings, fork]
---

# The Python binding

This fork ships **one** binding: `src/okf` (Python) — native, thin (~1,900
lines), and the writer of the [catalog](catalog.md).

The original work ships five bindings (R, Python, Rust, C++, MATLAB) held
byte-identical by a shared corpus, so that a change is portable across all of
them. This fork drops the other four. The reason is cost, not disagreement:
holding five implementations in step means two to five implementations per
change and CI in four languages Foodini does not write. That trade only pays
when the bindings are the product; here the tool is.

What survives is the part that was worth keeping. The
[conformance corpus](conformance.md) is language-neutral, and its Python checker
is standalone, so it remains the regression gate for every change — see
[determinism](determinism.md) for why that matters. The catalog
[schema](catalog.md) is likewise unchanged, so a catalog written here is still
readable by any conformant implementation, including the original's.

Install is correspondingly simpler — see [install](install.md). Point it at any
[source](sources.md) and [query](query.md) or [render](render.md) the result.
