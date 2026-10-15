---
type: Concept
title: The concept graph
description: Markdown links become resolved/broken edges — surfaced as backlinks, impact, clusters, and the graph view.
timestamp: 2026-06-23T00:00:00Z
tags: [graph, links, backlinks]
---

# The concept graph

Every markdown link is resolved against the bundle and stored in `okf_link` as a
resolved or broken edge (consumers must tolerate broken links per
[the spec](okf-spec.md)). That graph is the heart of the [catalog](catalog.md).

Deterministic helpers surface it: `backlinks` ("linked from"), `impact`
(inbound/outbound/transitive ripple of a concept), and `clusters` (communities
via reproducible label propagation). The same graph drives [rendering](render.md)
— the interactive graph view and Mermaid export — and the [context](context.md)
primitive. No relationships are inferred ([determinism](determinism.md)); only
the links you wrote.

## Edge kinds

Every `okf_link` row carries a `kind`. A link inside a generator
Relationships-table row (first cell `calls`, `called_by` or `related`, second
cell the link) takes that row's type —
`calls` or `related` (`related (AI)` folds into `related`); a `called_by` row is
the reverse of a `calls` row on the other page and is **not stored**, which is
what kept the undirected union from meaning anything. A plain link is `link`,
or `index` when it sits in a directory `index.md`; an import statement is
`import`.

`backlinks` and `context` follow `DEFAULT_KINDS` (everything but `index`);
`impact` follows `CODE_KINDS` (`calls` + `import`) in reverse, which is what a
change can actually hit. Both take `kinds` and `include_tests`; test pages
(recognised by path: `tests/`, `test_*`, `*.test.*`, `*.spec.*`) are dropped by
default. An existing catalog gains the column on its next ingest.

## Import edges

A concept may list import statements under a `## Imports` heading, one per
bullet (`- \`from pkg.mod import name\``), which is how okf-generator renders a
module's imports. Each imported name is resolved to the concept whose path ends
with the dotted module path — `pkg/mod/name.md`, then `pkg/mod/__init__/name.md`,
then the module page itself — and stored in `okf_link` as a resolved edge whose
`dst_raw` is the statement. So a bundle that holds several codebases side by
side gets edges between them, which a per-codebase call graph cannot provide.

Only resolved edges are stored: an import of the standard library or of a
package outside the bundle is not a broken link, so it is neither a row nor a
finding, and `links_total` / `links_broken` count markdown links only. Among
several matches the one nearest the importer wins (its own subtree before a
sibling's), then the more specific one; an exact tie resolves to nothing. A
`Dependency` concept is a manifest entry, not a module, and is never a target.
A standard-library module is never looked up, and a bare single-segment name
(`import httpx`) crosses into another codebase only where it is a top-level
package there (`httpx/__init__.md` exists and the directory above is not a
package) — a codebase is the `git:repo:` tag when present, else the first path
segment. Multi-segment names cross freely. The resolution is by path suffix
and is deterministic.
