#!/usr/bin/env python3
"""Static check: every read of an okf_* table is scoped to one bundle.

Added by Foodini 2026-08-23. The catalog schema is multi-bundle - every table
carries bundle_id, okf_concept is keyed by (bundle_id, path) - but 28 of 31 reads
omitted the predicate. Because paths collide across bundles (`src/main.py` exists
in many repos), an unscoped read over two bundles returns a plausible, confidently
wrong answer. The `twobundles` conformance fixture catches that behaviourally;
this catches it statically, including on code paths no fixture exercises.

Walks the AST and reconstructs each SQL literal, so a predicate on a continuation
line is not mistaken for a missing one - which a line-based grep gets wrong.

Run: python conformance/check_scoping.py   (exit 0 = pass)
"""
import ast
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src", "okf")
TABLES = ("okf_concept", "okf_link", "okf_validation", "okf_chunk", "okf_bundle")

# Statements that are deliberately NOT bundle-scoped. Adding an entry has to be a
# conscious edit with a reason - that is the point of keeping this list here
# rather than inferring intent from a comment.
ALLOWED = {
    ("diff.py", "SELECT DISTINCT bundle_id FROM okf_concept"):
        "diff discovers which bundles a catalog holds; scoping it would defeat it",
    ("okf.py", "SELECT bundle_id FROM okf_bundle ORDER BY bundle_id"):
        "resolve_bundle enumerates candidates - it is the resolver itself",
}


def literal(node):
    """Flatten a string node; f-string placeholders become '?'."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        return "".join(literal(v) if not isinstance(v, ast.FormattedValue) else "?"
                       for v in node.values)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        a, b = literal(node.left), literal(node.right)
        if a is not None or b is not None:
            return (a or "") + (b or "")
    return None


fails, checked = [], 0
for name in sorted(os.listdir(SRC)):
    if not name.endswith(".py"):
        continue
    path = os.path.join(SRC, name)
    with open(path, encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        if not (isinstance(fn, ast.Attribute)
                and fn.attr in ("execute", "executemany") and node.args):
            continue
        sql = literal(node.args[0])
        if not sql or not any(t in sql for t in TABLES):
            continue
        flat = " ".join(sql.split())
        verb = flat.split(" ", 1)[0].upper()
        if verb in ("CREATE", "DROP", "INSERT"):
            # DDL is bundle-agnostic; INSERT supplies bundle_id as a value.
            continue
        checked += 1
        if "bundle_id = ?" in flat or "bundle_id=?" in flat:
            continue
        if (name, flat) in ALLOWED:
            continue
        fails.append(f"{name}:{node.lineno}  {verb}  {flat[:100]}")

if fails:
    print("FAIL - unscoped okf_* statement(s); add bundle_id = ? or an ALLOWED "
          "entry with a reason:")
    print("  " + "\n  ".join(fails))
    sys.exit(1)
print(f"PASS - all {checked} okf_* reads/writes are bundle-scoped "
      f"({len(ALLOWED)} deliberate exceptions)")
