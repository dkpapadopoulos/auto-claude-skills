#!/usr/bin/env python3
"""Score the sticky-repeat screen (#333, stage A). Run ONCE, after collection closes.

Inputs: the key written by rows.py, two labellers' files and the owner's calibration file.
A label file is JSONL: {"row_id": ..., "label": "WARRANTED" | "NOT_WARRANTED" |
"INSUFFICIENT_CONTEXT"}. A row is DECIDED when both labellers give the same one of the
first two labels.

The verdict is one of:
  PASS          the rule may go to the randomized trial (stage B). It does NOT license
                turning suppression on: labels say whether a mandate was warranted, not
                what happens when the reminder is gone.
  STOP          the rule fails the screen; it stays in shadow or is removed.
  INCONCLUSIVE  the data cannot carry a verdict (too few rows, too few sessions, labellers
                disagree, or the owner disagrees with them).

Every threshold is in THRESHOLDS below and is the pre-registered value. Prints counts.

Usage:
  score.py --key FILE --labels FILE --labels FILE --owner FILE
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import collections  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402

LABELS = ("WARRANTED", "NOT_WARRANTED", "INSUFFICIENT_CONTEXT")
THRESHOLDS = {
    "min_hidden_rows": 40,            # K0: fewer is INCONCLUSIVE
    "min_sessions": 10,               # K0: hidden rows must come from at least this many sessions
    "max_one_session_share": 0.25,    # K0: no single session may supply more than this share of them
    "min_kappa": 0.60,                # K0: Cohen's kappa over all labelled rows
    "min_owner_rows": 20,             # K0: owner calibration rows
    "min_owner_agreement": 0.80,      # K0: owner agrees with the labellers' decided label
    "min_reach": 0.15,                # K1: hidden rows / all mandated rows
    "min_not_warranted": 0.75,        # K2: DECIDED NOT_WARRANTED / ALL hidden rows (not: of decided)
    "max_warranted": 0.10,            # K2b: DECIDED WARRANTED / all hidden rows
    "max_warranted_and_acted": 0.05,  # K3: WARRANTED and followed by a same-turn invocation / all hidden rows
}


def read_jsonl(path):
    out = []
    with open(path, encoding="utf-8") as src:
        for line in src:
            if line.strip():
                out.append(json.loads(line))
    return out


def read_labels(path):
    labels = {}
    for item in read_jsonl(path):
        if item.get("label") not in LABELS:
            raise SystemExit(f"{path}: row {item.get('row_id')!r} has label {item.get('label')!r}; expected one of {LABELS}")
        if item["row_id"] in labels:
            raise SystemExit(f"{path}: row {item['row_id']!r} is labelled twice")
        labels[item["row_id"]] = item["label"]
    return labels


def kappa(a, b, ids):
    """Cohen's kappa over the rows both labelled. None when it is undefined."""
    n = len(ids)
    if n == 0:
        return None
    po = sum(1 for i in ids if a[i] == b[i]) / n
    pe = sum((sum(1 for i in ids if a[i] == lab) / n) * (sum(1 for i in ids if b[i] == lab) / n) for lab in LABELS)
    return None if pe >= 1 else (po - pe) / (1 - pe)


def upper_bound(k, n, alpha=0.05):
    """One-sided exact (Clopper-Pearson) upper bound on a proportion, by bisection."""
    if n == 0:
        return 1.0
    if k >= n:
        return 1.0

    def cdf(p):
        return sum(math.comb(n, i) * p ** i * (1 - p) ** (n - i) for i in range(k + 1))

    lo, hi = k / n, 1.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if cdf(mid) > alpha:
            lo = mid
        else:
            hi = mid
    return hi


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--key", required=True)
    ap.add_argument("--labels", required=True, action="append")
    ap.add_argument("--owner", required=True)
    args = ap.parse_args()
    if len(args.labels) != 2:
        raise SystemExit("exactly two --labels files are required")
    T = THRESHOLDS

    key = {k["row_id"]: k for k in read_jsonl(args.key)}
    la, lb = read_labels(args.labels[0]), read_labels(args.labels[1])
    owner = read_labels(args.owner)
    missing = [i for i in key if i not in la or i not in lb]
    if missing:
        raise SystemExit(f"{len(missing)} rows are not labelled by both labellers; every mandated row must be")
    extra = [i for i in list(la) + list(lb) + list(owner) if i not in key]
    if extra:
        raise SystemExit(f"{len(extra)} labels name rows that are not in the key")

    ids = sorted(key)
    decided = {i: la[i] for i in ids if la[i] == lb[i] and la[i] in ("WARRANTED", "NOT_WARRANTED")}
    hidden = [i for i in ids if key[i]["would_hide"]]
    n_all, n_hid = len(ids), len(hidden)
    per_session = collections.Counter(key[i]["session"] for i in hidden)
    top_share = (max(per_session.values()) / n_hid) if n_hid else 0.0
    kap = kappa(la, lb, ids)

    hid_not = sum(1 for i in hidden if decided.get(i) == "NOT_WARRANTED")
    hid_war = sum(1 for i in hidden if decided.get(i) == "WARRANTED")
    hid_und = n_hid - hid_not - hid_war
    hid_war_acted = sum(1 for i in hidden if decided.get(i) == "WARRANTED" and key[i]["invoked_same_turn"])
    hid_not_acted = sum(1 for i in hidden if decided.get(i) == "NOT_WARRANTED" and key[i]["invoked_same_turn"])
    rest = [i for i in ids if not key[i]["would_hide"]]
    rest_not = sum(1 for i in rest if decided.get(i) == "NOT_WARRANTED")
    rest_war = sum(1 for i in rest if decided.get(i) == "WARRANTED")
    chars_all = sum(key[i]["block_chars"] for i in ids)
    chars_hid = sum(key[i]["block_chars"] for i in hidden)

    own_ids = [i for i in owner if i in decided]
    own_agree = sum(1 for i in own_ids if owner[i] == decided[i])
    own_rate = (own_agree / len(own_ids)) if own_ids else 0.0

    print(f"mandated rows                                  {n_all}")
    print(f"rows the rule would hide                       {n_hid}  ({n_hid / n_all:.1%} of mandated)" if n_all else "no rows")
    print(f"  from sessions                                {len(per_session)}  (largest single session: {top_share:.0%} of them)")
    print(f"  block characters hidden                      {chars_hid}  ({(chars_hid / chars_all if chars_all else 0):.1%} of all mandated block text)")
    print(f"labeller agreement (Cohen's kappa, all rows)   {'undefined' if kap is None else f'{kap:.2f}'}")
    print(f"hidden, decided NOT_WARRANTED (unwanted removed) {hid_not}  ({(hid_not / n_hid if n_hid else 0):.1%} of hidden)")
    print(f"hidden, decided WARRANTED (work orders hidden)   {hid_war}  ({(hid_war / n_hid if n_hid else 0):.1%} of hidden; one-sided 95% upper bound {upper_bound(hid_war, n_hid):.1%})")
    print(f"hidden, not decided                              {hid_und}  ({(hid_und / n_hid if n_hid else 0):.1%} of hidden)")
    print(f"hidden, WARRANTED and invoked the same turn      {hid_war_acted}")
    print(f"hidden, NOT_WARRANTED and invoked the same turn  {hid_not_acted}")
    print(f"not hidden: decided NOT_WARRANTED / WARRANTED    {rest_not} / {rest_war}  (what the rule leaves)")
    print(f"owner calibration: agrees on {own_agree} of {len(own_ids)} decided rows  ({len(owner)} labelled)")
    by_skill = collections.Counter(key[i]["skill"] for i in hidden)
    print("hidden rows by skill: " + ", ".join(f"{s} {n}" for s, n in by_skill.most_common()))

    inconclusive = []
    if n_hid < T["min_hidden_rows"]:
        inconclusive.append(f"only {n_hid} hidden rows (need {T['min_hidden_rows']})")
    if len(per_session) < T["min_sessions"]:
        inconclusive.append(f"hidden rows come from {len(per_session)} sessions (need {T['min_sessions']})")
    if n_hid and top_share > T["max_one_session_share"]:
        inconclusive.append(f"one session supplies {top_share:.0%} of hidden rows (limit {T['max_one_session_share']:.0%})")
    if kap is None or kap < T["min_kappa"]:
        inconclusive.append(f"kappa {'undefined' if kap is None else f'{kap:.2f}'} (need {T['min_kappa']:.2f})")
    if len(owner) < T["min_owner_rows"]:
        inconclusive.append(f"owner labelled {len(owner)} rows (need {T['min_owner_rows']})")
    elif not own_ids or own_rate < T["min_owner_agreement"]:
        inconclusive.append(f"owner agrees on {own_agree} of {len(own_ids)} decided rows (need {T['min_owner_agreement']:.0%})")
    if inconclusive:
        print("\nVERDICT: INCONCLUSIVE")
        for why in inconclusive:
            print(f"  - {why}")
        return 3

    checks = [
        ("K1 reach", n_hid / n_all >= T["min_reach"], f"{n_hid / n_all:.1%} of mandated rows hidden (need {T['min_reach']:.0%})"),
        ("K2 unwanted", hid_not / n_hid >= T["min_not_warranted"], f"{hid_not / n_hid:.1%} of ALL hidden rows decided NOT_WARRANTED (need {T['min_not_warranted']:.0%})"),
        ("K2b warranted", hid_war / n_hid <= T["max_warranted"], f"{hid_war / n_hid:.1%} of hidden rows decided WARRANTED (limit {T['max_warranted']:.0%})"),
        ("K3 acted", hid_war_acted <= math.floor(T["max_warranted_and_acted"] * n_hid), f"{hid_war_acted} WARRANTED and acted on (limit {math.floor(T['max_warranted_and_acted'] * n_hid)} of {n_hid})"),
    ]
    ok = all(passed for _, passed, _ in checks)
    print(f"\nVERDICT: {'PASS (to the randomized trial; NOT a licence to suppress)' if ok else 'STOP'}")
    for name, passed, detail in checks:
        print(f"  {'ok  ' if passed else 'FAIL'} {name}: {detail}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
