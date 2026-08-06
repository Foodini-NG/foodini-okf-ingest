---
type: Metric
title: "Widget throughput"
description: "Widgets processed per day, v0.2-style provenance."
generated: { by: reference_agent/test-1, at: 2026-08-01T00:00:00Z }
sources:
  - id: widget-schema
    resource: https://example.com/widget/schema
    title: Widget export schema
    author: team:widget-docs
    usage_count: 5000
    last_modified: 2026-05-30
  - resource: bigquery://project/widgets/events
usage_window: { from: 2026-06-01, to: 2026-06-30 }
verified:
  - by: human:reviewer
    at: 2026-07-15T00:00:00Z
status: stable
stale_after: 2027-01-01
---

# Widget throughput

Pure v0.2 concept: provenance in `sources`, freshness in `generated.at`
(no legacy `timestamp` -- consumers must fall back). See the
[index](/index.md) and the [legacy concept](/legacy.md).
