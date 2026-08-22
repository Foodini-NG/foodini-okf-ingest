---
type: Reference
title: Install
description: Install the Python package from a clone with uv, or run it without installing.
timestamp: 2026-08-22T00:00:00Z
tags: [install, uv, python]
---

# Install

Python 3.14 or newer. The project is uv-managed.

```bash
git clone git@github.com:Foodini-NG/foodini-okf-ingest.git
cd foodini-okf-ingest
uv venv --python 3.14
uv pip install -e ".[html]"       # [html] adds the markdown engine for rendering
```

That puts the **`okf-ingest`** command on PATH inside `.venv`, plus the
importable `okf` package.

- **Command name.** The command is `okf-ingest`, not `okf`. The original work
  installs a bare `okf`, which collides with okf-generator — the collision is
  why this fork renamed it.
- **Distribution name.** `foodini-okf-ingest`. It is not on PyPI; install from a
  clone.
- **No install:** `PYTHONPATH=src python -m okf …` for the [CLI](cli.md).

Dependencies are deliberately light — yaml + DuckDB at the core, with an
embedder and a markdown engine optional. Once installed, point it at any
[source](sources.md).
