---
type: Reference
title: Conformance & parity
description: The golden-bundle corpus that gates every change, and what OKF conformance the tool enforces.
timestamp: 2026-08-22T00:00:00Z
tags: [conformance, parity, testing]
---

# Conformance & parity

A bundle is **conformant** iff every non-reserved `.md` has parseable YAML
frontmatter with a non-empty `type`. Everything else (missing recommended
fields, broken links, orphans, missing `index.md`) is a *finding*, never a
rejection — permissive per OKF v0.1.

The [Python binding](bindings.md) is held to its expected
[catalogs](catalog.md) by a language-agnostic conformance suite — golden bundles
plus expected JSON, including a `content_hash` parity lock and a
hidden-directory guard. Dot-dirs (`.git`/`.github`) are skipped, files sort in a
fixed order, and links resolve identically run to run. This is what makes the
[determinism](determinism.md) claim testable rather than aspirational, and it is
checked in CI alongside the [CLI](cli.md) smokes.

The corpus originally existed to prove *cross-language* parity. This fork has
one binding, so it now serves as a behavioural regression gate instead: any
change that moves a conformance-asserted value — summary fields, content hashes,
findings, link resolutions, PPR scores, diff deltas — has to update the expected
JSON deliberately and say why. Because those values were pinned to be
reproducible in five independent implementations, they are unusually good
regression anchors.
