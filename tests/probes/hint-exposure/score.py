#!/usr/bin/env python3
"""Score the #412 Q1 replay and the Q2 counts (pre-registration
docs/plans/2026-10-31-frontend-hint-exposure-prereg.md, D1, D2, D3, D8).

Labels (D2): a row is UI or NOT when L1 and L2 agree on it; otherwise, including any
MALFORMED answer, the owner's label decides (the 2-of-3 majority). A row with neither is
unresolved, and any unresolved row makes Q1 cannot-check.

For each route and variant in --variants, a row matches when its line number appears in
<draw-dir>/replay-<route>-<variant>/hits.tsv (q1.sh writes these). With weights w from
rows.jsonl: precision = sum(w*UI*match) / sum(w*match), recall = sum(w*UI*match) / sum(w*UI).

D1, per variant against V0 on the same rows: (A) delta recall >= 0.15 and delta precision >= 0,
or (B) delta precision > 0 and delta recall >= -0.05. Each delta gets a stratified bootstrap
95% percentile interval (stratum A and the stratum B sample resampled separately, weights
fixed, V0 and the variant on the same resample). A condition passes when the interval clears
its threshold, fails when it lies wholly on the wrong side, and is otherwise inconclusive; a
branch is the AND and the variant the OR of these, three-valued. A resample in which a delta is
undefined is dropped and counted; above 5% dropped, that delta's conditions are inconclusive.
A branch that cannot pass whatever the variant does (A when V0 recall > 0.85, B when V0
precision is 1) is scored as failing and noted "unreachable". A variant whose triggers equal
V0's is identical-to-V0 and not scored. An undefined point estimate (no UI rows, or a variant or
V0 with no matches) is cannot-check.

--worksheet FILE writes the rows the owner must label (L1 and L2 disagree, or either is
MALFORMED or FAILED) as `<id><TAB><prompt>` and nothing else, so the owner labels blind to the
stratum, routes, weights and the labellers' votes. It holds prompt text: mode 0600, and a path
inside a git repository is refused (exit 2).

Exit 0 when every verdict was reached, 3 when any is cannot-check (unresolved labels, a
missing replay, an undefined estimate), 2 on bad input. Prints counts only, never prompts.

Usage:
  score.py --draw-dir DIR --variants FILE --labels L1.tsv L2.tsv [--owner FILE] --seed INT
           [--resamples 2000] [--worksheet FILE]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import os  # noqa: E402
import random  # noqa: E402
import re  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "real-prompt-replay"))
from extract import open_private, refuse_repo_path  # noqa: E402

THRESHOLDS = {"A": (("recall", 0.15, False), ("precision", 0.0, False)),
              "B": (("precision", 0.0, True), ("recall", -0.05, False))}
MAX_DROPPED = 0.05
LABELS = ("UI", "NOT")


def read_tsv(path):
    out = {}
    if path is None:
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 2:
                out[parts[0]] = parts[1]
    return out


def resolve(rows, l1, l2, owner):
    labels, agreed, by_owner, unresolved = {}, 0, 0, 0
    for r in rows:
        a, b = l1.get(r["id"]), l2.get(r["id"])
        if a == b and a in LABELS:
            labels[r["id"]] = a
            agreed += 1
        elif owner.get(r["id"]) in LABELS:
            labels[r["id"]] = owner[r["id"]]
            by_owner += 1
        else:
            unresolved += 1
    return labels, agreed, by_owner, unresolved


def read_hits(path, n):
    hits = [0] * n
    with open(path, encoding="utf-8") as f:
        for line in f:
            k = line.split("\t", 1)[0]
            if k.isdigit() and 1 <= int(k) <= n:
                hits[int(k) - 1] = 1
    return hits


def measures(idx, w, ui, m):
    """(precision, recall) over the row indices idx; None where undefined."""
    tp = sum(w[i] for i in idx if ui[i] and m[i])
    pos = sum(w[i] for i in idx if m[i])
    rel = sum(w[i] for i in idx if ui[i])
    return (tp / pos if pos else None), (tp / rel if rel else None)


def fmt(x):
    return "undefined" if x is None else "%.4f" % x


def percentile(sorted_vals, q):
    k = max(0, math.ceil(q * len(sorted_vals)) - 1)
    return sorted_vals[k]


def condition(ci, threshold, strict):
    lo, hi = ci
    if (lo > threshold) if strict else (lo >= threshold):
        return "pass"
    if (hi <= threshold) if strict else (hi < threshold):
        return "fail"
    return "inconclusive"


def all3(vals):
    if "fail" in vals:
        return "fail"
    return "pass" if all(v == "pass" for v in vals) else "inconclusive"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--draw-dir", required=True)
    ap.add_argument("--variants", required=True)
    ap.add_argument("--labels", nargs=2, required=True, metavar=("L1", "L2"))
    ap.add_argument("--owner")
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--resamples", type=int, default=2000)
    ap.add_argument("--worksheet")
    a = ap.parse_args()
    if a.worksheet and refuse_repo_path(os.path.dirname(os.path.abspath(a.worksheet))):
        return 2
    try:
        with open(os.path.join(a.draw_dir, "rows.jsonl"), encoding="utf-8") as f:
            rows = [json.loads(line) for line in f if line.strip()]
        routes = json.load(open(a.variants, encoding="utf-8"))["routes"]
        l1, l2, owner = read_tsv(a.labels[0]), read_tsv(a.labels[1]), read_tsv(a.owner)
    except (OSError, ValueError, KeyError) as e:
        print("bad input: %s" % e, file=sys.stderr)
        return 2
    labels, agreed, by_owner, unresolved = resolve(rows, l1, l2, owner)
    print("labels: rows %d agreed %d owner-resolved %d unresolved %d" % (len(rows), agreed, by_owner, unresolved))
    if a.worksheet:
        with open_private(a.worksheet) as f:
            for r in sorted(rows, key=lambda r: r["id"]):
                if r["id"] not in labels:
                    f.write("%s\t%s\n" % (r["id"], re.sub(r"[\t\r\n]+", " ", r["prompt"])))
        print("worksheet: %d rows for the owner" % unresolved)
    if unresolved:
        print("Q1: cannot-check (unresolved labels)")
        return 3
    n = len(rows)
    w = [float(r["weight"]) for r in rows]
    ui = [1 if labels[r["id"]] == "UI" else 0 for r in rows]
    strata = {s: [i for i in range(n) if rows[i]["stratum"] == s] for s in ("A", "B")}
    named = {True: [i for i in range(n) if rows[i].get("named")], False: [i for i in range(n) if not rows[i].get("named")]}
    every = list(range(n))
    rng = random.Random(a.seed)
    samples = [[i for s in ("A", "B") for i in (rng.choice(strata[s]) for _ in strata[s])] for _ in range(a.resamples)]
    rc = 0
    for route in sorted(routes):
        spec = routes[route]
        hits = {}
        for v in ("V0", "V1", "V2"):
            path = os.path.join(a.draw_dir, "replay-%s-%s" % (route, v), "hits.tsv")
            try:
                hits[v] = read_hits(path, n)
            except OSError:
                print("D1 %s %s: cannot-check (no replay at %s)" % (route, v, path))
                rc = 3
        if "V0" not in hits:
            continue
        p0, r0 = measures(every, w, ui, hits["V0"])
        qualifying = []
        for v in ("V0", "V1", "V2"):
            if v not in hits:
                continue
            m = hits[v]
            p, r = measures(every, w, ui, m)
            counts = []
            for s in ("A", "B"):
                ix = strata[s]
                counts.append("stratum %s rows %d ui %d match %d ui&match %d" % (
                    s, len(ix), sum(ui[i] for i in ix), sum(m[i] for i in ix), sum(1 for i in ix if ui[i] and m[i])))
            print("%s %s: precision %s recall %s" % (route, v, fmt(p), fmt(r)))
            print("  " + "; ".join(counts))
            parts = []
            for flag, label in ((True, "named"), (False, "unnamed")):
                pn, rn = measures(named[flag], w, ui, m)
                parts.append("%s: precision %s recall %s" % (label, fmt(pn), fmt(rn)))
            print("  " + "; ".join(parts))
            if v == "V0":
                continue
            if spec[v] == spec["V0"]:
                print("D1 %s %s: identical-to-V0" % (route, v))
                continue
            if None in (p0, r0, p, r):
                print("D1 %s %s: cannot-check (undefined estimate)" % (route, v))
                rc = 3
                continue
            deltas = {"precision": [], "recall": []}
            for idx in samples:
                bp0, br0 = measures(idx, w, ui, hits["V0"])
                bp, br = measures(idx, w, ui, m)
                if bp0 is not None and bp is not None:
                    deltas["precision"].append(round(bp - bp0, 12))
                if br0 is not None and br is not None:
                    deltas["recall"].append(round(br - br0, 12))
            cis, dropped = {}, {}
            for q in ("precision", "recall"):
                vals = sorted(deltas[q])
                dropped[q] = a.resamples - len(vals)
                cis[q] = (percentile(vals, 0.025), percentile(vals, 0.975)) if vals else None
            point = {"precision": round(p - p0, 12), "recall": round(r - r0, 12)}
            print("  " + "; ".join("delta %s %+.4f [%s] (dropped %d/%d)" % (
                q, point[q], "%+.4f, %+.4f" % cis[q] if cis[q] else "none", dropped[q], a.resamples)
                for q in ("precision", "recall")))
            notes = [b for b, bad in (("A", r0 > 0.85), ("B", p0 >= 1.0)) if bad]
            branch = {}
            for b, conds in THRESHOLDS.items():
                vals = []
                for q, t, strict in conds:
                    if cis[q] is None or dropped[q] > MAX_DROPPED * a.resamples:
                        vals.append("inconclusive")
                    else:
                        vals.append(condition(cis[q], t, strict))
                branch[b] = "fail" if b in notes else all3(vals)
            if branch["A"] == "pass" or branch["B"] == "pass":
                verdict = "qualifies-" + "+".join(b for b in ("A", "B") if branch[b] == "pass")
                qualifying.append((r, p, v))
            elif branch["A"] == "fail" and branch["B"] == "fail":
                verdict = "fails"
            else:
                verdict = "inconclusive"
            print("D1 %s %s: %s%s" % (route, v, verdict, "  unreachable: " + " ".join(notes) if notes else ""))
        qualifying.sort(key=lambda t: (-t[0], -t[1], t[2]))
        print("rank %s: %s" % (route, ", ".join(t[2] for t in qualifying) or "none"))
    # Q2 (D8): descriptive, over UI-labelled rows.
    for skill in ("frontend-design", "runtime-validation"):
        tally = {}
        for i, row in enumerate(rows):
            if ui[i] and skill in row.get("listed", []):
                cls = row.get("q2", {}).get(skill, "unknown")
                tally[cls] = tally.get(cls, 0) + 1
        print("Q2 %s listed on UI rows: %s" % (skill, ", ".join(
            "%s %d" % (c, tally.get(c, 0)) for c in ("loaded-earlier", "in-turn", "direct-validation", "later", "unknown"))))
    return rc


if __name__ == "__main__":
    sys.exit(main())
