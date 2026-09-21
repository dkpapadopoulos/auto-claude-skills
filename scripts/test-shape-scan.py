#!/usr/bin/env python3
"""
test-shape-scan.py — classify each tests/*.sh by where its assertions live.

tests/test-suite-wiring.sh can only see assertions inside a `test_*` function
that the file invokes. Files that run most of their assertions at top level are
a DIFFERENT RUNNER SHAPE: the sweep's verdict on them means much less, and
folding that into a clean pass hides the limit.

This is NOT a defect detector. A top-level assertion cannot have the
defined-but-never-invoked defect — it runs as the script runs. What the old
hardcoded floor of 5 accidentally provided was a shape SIGNAL, and this
reproduces that signal precisely instead of by proxy.

Prints one `<name> <inside> <outside>` line per mixed-shape file.
"""
import glob, os, re, sys

DEF = re.compile(r'^(?:function\s+)?(test_[A-Za-z0-9_]+)\s*(?:\(\s*\))?\s*\{?\s*$')
ASSERT = re.compile(r'^\s*(assert_|_record_)')


def classify(path):
    inside = outside = 0
    depth = 0
    in_fn = False
    for line in open(path, encoding="utf-8", errors="replace"):
        if not in_fn and DEF.match(line.rstrip()):
            in_fn, depth = True, 0
        if in_fn:
            depth += line.count("{") - line.count("}")
            if ASSERT.match(line):
                inside += 1
            # One condition, not two. This was written as two branches whose
            # bodies are identical and whose first condition is strictly
            # subsumed by the second — anything matching `"{" not in line` also
            # matches without it — so the first arm could never change an
            # outcome. Collapsing is behaviour-preserving, verified by
            # comparing this script's output over tests/ before and after.
            if depth <= 0 and "}" in line:
                in_fn = False
            continue
        if ASSERT.match(line):
            outside += 1
    return inside, outside


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "tests"
    for path in sorted(glob.glob(os.path.join(root, "test-*.sh"))):
        name = os.path.basename(path)
        has_def = any(DEF.match(l.rstrip()) for l in open(path, encoding="utf-8", errors="replace"))
        if not has_def:
            continue
        inside, outside = classify(path)
        # Mixed shape: most assertions run outside any test function, or the
        # file defines test functions yet runs no assertion this matcher sees
        # at all (its work is in top-level loops or another helper).
        if outside > inside or (inside == 0 and outside == 0):
            print("%s %d %d" % (name, inside, outside))
    return 0


if __name__ == "__main__":
    sys.exit(main())
