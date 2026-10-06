#!/usr/bin/env python3
"""Draw the owner's calibration rows for the sticky-repeat screen (#333, stage A).

The pre-registration has the owner label 20 rows blind, "drawn at random from the rows both
labellers decided". This does the drawing, so nobody chooses them:

  - a row is DECIDED when both labellers gave it the same label and that label is WARRANTED
    or NOT_WARRANTED;
  - 20 are drawn (all of them, if there are fewer) with a seed derived from the row ids
    themselves, so the draw is reproducible and no one picked the seed;
  - what is written is the labeller's view of each drawn row and nothing else: no label, no
    field of the key, in an order unrelated to either.

Reads --rows (the labeller's view from rows.py) and the two --labels files. It does NOT read
the key. Prints counts only. The output holds prompt text: a path inside a git repository is
refused (exit 2), and the file is written mode 0600.

Usage:
  owner_sample.py --rows FILE --labels FILE --labels FILE --out FILE [--n 20]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import random  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import open_private, refuse_repo_path  # noqa: E402

DECIDABLE = ("WARRANTED", "NOT_WARRANTED")


def read_jsonl(path):
    out = []
    with open(path, encoding="utf-8") as src:
        for n, line in enumerate(src, 1):
            if line.strip():
                item = json.loads(line)
                if not isinstance(item, dict) or not isinstance(item.get("row_id"), str) or not item["row_id"]:
                    raise ValueError(f"{path}: line {n} is not an object with a row_id")
                out.append(item)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", required=True)
    ap.add_argument("--labels", required=True, action="append")
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=20)
    args = ap.parse_args()
    if len(args.labels) != 2:
        print("exactly two --labels files are required", file=sys.stderr)
        return 2
    if args.n < 1:
        print("--n must be at least 1", file=sys.stderr)
        return 2
    if refuse_repo_path(args.out):
        return 2

    rows = {r["row_id"]: r for r in read_jsonl(args.rows)}
    la = {x["row_id"]: x.get("label") for x in read_jsonl(args.labels[0])}
    lb = {x["row_id"]: x.get("label") for x in read_jsonl(args.labels[1])}
    decided = sorted(i for i in rows if la.get(i) == lb.get(i) and la.get(i) in DECIDABLE)
    seed = hashlib.sha256("\x1f".join(decided).encode()).hexdigest()
    rng = random.Random(seed)
    drawn = rng.sample(decided, min(args.n, len(decided)))
    with open_private(args.out) as out:
        for i in drawn:
            out.write(json.dumps(rows[i], ensure_ascii=False) + "\n")
    print(f"{len(rows):6d}  rows")
    print(f"{len(decided):6d}  decided by both labellers")
    print(f"{len(drawn):6d}  drawn for the owner (asked for {args.n})")
    print(f"seed (from the decided row ids): {seed[:16]}")
    if len(drawn) < args.n:
        print(f"FEWER THAN {args.n} decided rows exist: the owner floor in score.py cannot be met and stage A will read INCONCLUSIVE.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as err:  # noqa: BLE001 -- deliberately everything
        print(f"cannot read the inputs: {type(err).__name__}: {err}", file=sys.stderr)
        sys.exit(2)
