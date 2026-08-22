---
type: Index
title: Minimal bundle
description: A bundle with no concept documents, so no links and no findings.
timestamp: 2026-08-22T00:00:00Z
tags: [minimal, edge-case]
---

# Minimal bundle

Reserved documents only. `validate` skips reserved files, so this bundle yields
**zero** links and **zero** findings while still being conformant — the degenerate
case that catches a batch-insert path which cannot accept an empty row set.
