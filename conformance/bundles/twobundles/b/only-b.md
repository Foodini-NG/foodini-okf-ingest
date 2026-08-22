---
type: Concept
title: Only in B
description: Present in bundle B only, and links to the colliding path so an unscoped read is observable.
timestamp: 2026-08-23T00:00:00Z
---

# Only in B

Also points at [the shared name](shared.md), so inbound links to `shared.md`
differ between the two bundles. Without that, DISTINCT collapses the collision
and an unscoped read returns the right answer by accident.

Marker: betamarker
