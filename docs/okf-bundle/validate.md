---
type: Reference
title: Validate
description: The conformance lint — errors, warnings, filters and a summary, with CI exit codes.
timestamp: 2026-08-23T00:00:00Z
tags: [validate, conformance, lint]
---

# Validate

`okf-ingest validate` checks a bundle against [the OKF spec](okf-spec.md): the hard rule
(parseable frontmatter with a non-empty `type`) produces **errors**; everything
else — missing recommended fields, broken links, orphans, non-ISO timestamps —
produces **warnings**, never a rejection.

Exit codes make it CI-friendly: `0` conformant, `1` on errors (or warnings under
`--strict`), `2` bad invocation. The findings are stored in [the
catalog](catalog.md) and reused by [doctor](doctor.md), which adds a health score
and maintenance checks on top. All of it is [deterministic](determinism.md).

## Reading the findings

A bundle that mixes hand-written and generated concepts produces a lot of
warnings, and almost all of them are expected — a generated concept with no
description is not a defect. Two flags make that tractable:

- `--summary` reports counts by severity, by rule and by leading path prefix
  instead of every line, so "what kind of problem, and where?" is one command.
- `--severity`, `--rule`, `--exclude-rule`, `--path` and `--exclude-path` narrow
  the set. Path patterns are globs, except that a pattern with no wildcard is
  treated as a prefix — so `standards/` and `github-repositories/*/*` both work.

This makes a CI gate expressible directly: *are the hand-written concepts clean,
ignoring the generated ones?*

```bash
okf-ingest validate ./bundle --strict --exclude-path 'generated/*/*'
```

**Filters change what is reported, never what conformance is judged on.**
`conformant` and the error count are always computed over every finding, so
hiding an error cannot make a bundle look conformant, and a `--strict` run that
excluded errors still exits non-zero. A filtered run always prints how many
findings it suppressed.
