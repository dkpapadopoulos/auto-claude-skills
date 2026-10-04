#!/usr/bin/env python3
"""Analysis fixed by pre-registration R2. usage: analyze.py <model>"""
import sys, os, json, glob, itertools, statistics, math

ROOT = os.path.dirname(os.path.abspath(__file__))


def load(model):
    runs = {}
    for f in glob.glob(os.path.join(ROOT, "runs", model, "*", "*", "score.json")):
        s = json.load(open(f))
        if s["task"].startswith("zz-"):
            continue
        runs[(s["task"], s["arm"])] = s
    return runs


def signflip_p(diffs):
    """Exact two-sided paired sign-flip permutation p for the mean difference."""
    d = [x for x in diffs if x != 0]
    if not d:
        return 1.0
    obs = abs(sum(d))
    n = len(d); hit = 0
    for signs in itertools.product((1, -1), repeat=n):
        if abs(sum(s * x for s, x in zip(signs, d))) >= obs - 1e-12:
            hit += 1
    return hit / (2 ** n)


def binom_two_sided(k, n):
    """Exact two-sided sign/McNemar test p for k successes of n at p=0.5."""
    if n == 0:
        return 1.0
    tail = sum(math.comb(n, i) for i in range(0, min(k, n - k) + 1)) / 2 ** n
    return min(1.0, 2 * tail)


def compare(runs, x, y, tasks):
    pairs = [t for t in tasks if (t, x) in runs and (t, y) in runs
             and not runs[(t, x)]["harness_failure"] and not runs[(t, y)]["harness_failure"]]
    dq = [runs[(t, x)]["Q"] - runs[(t, y)]["Q"] for t in pairs]
    xw = sum(1 for t in pairs if runs[(t, x)]["Qbin"] and not runs[(t, y)]["Qbin"])
    yw = sum(1 for t in pairs if runs[(t, y)]["Qbin"] and not runs[(t, x)]["Qbin"])
    ratios = [runs[(t, x)]["tokens_total"] / runs[(t, y)]["tokens_total"] for t in pairs if runs[(t, y)]["tokens_total"]]
    usd = [runs[(t, x)]["cost_usd"] / runs[(t, y)]["cost_usd"] for t in pairs if runs[(t, y)].get("cost_usd") and runs[(t, x)].get("cost_usd")]
    wall = [runs[(t, x)]["wall_s"] / runs[(t, y)]["wall_s"] for t in pairs if runs[(t, y)]["wall_s"]]
    more = sum(1 for r in ratios if r > 1); less = sum(1 for r in ratios if r < 1)
    return {
        "pairs": len(pairs),
        "Q_mean_diff": round(sum(dq) / len(dq), 4) if dq else None,
        "Q_p_signflip": round(signflip_p(dq), 4),
        "Qbin_pass": {x: sum(1 for t in pairs if runs[(t, x)]["Qbin"]), y: sum(1 for t in pairs if runs[(t, y)]["Qbin"])},
        "Qbin_discordant": {f"{x}_only": xw, f"{y}_only": yw}, "Qbin_p_mcnemar": round(binom_two_sided(xw, xw + yw), 4),
        "tokens_ratio_median": round(statistics.median(ratios), 3) if ratios else None,
        "tokens_ratio_range": [round(min(ratios), 2), round(max(ratios), 2)] if ratios else None,
        "tokens_more_less": [more, less], "tokens_p_sign": round(binom_two_sided(more, more + less), 4),
        "usd_ratio_median": round(statistics.median(usd), 3) if usd else None,
        "wall_ratio_median": round(statistics.median(wall), 3) if wall else None,
    }


def main():
    model = sys.argv[1]
    runs = load(model)
    tasks = sorted({t for t, _ in runs})
    arms = ["A0", "A1", "A2"]
    print(f"# {model}: {len(tasks)} tasks, {len(runs)} runs\n")
    print("| task | " + " | ".join(f"{a} Q" for a in arms) + " | " + " | ".join(f"{a} ktok" for a in arms) + " | " + " | ".join(f"{a} $" for a in arms) + " | " + " | ".join(f"{a} skills/agents" for a in arms) + " |")
    print("|---|" + "---|" * 12)
    for t in tasks:
        row = [t]
        for a in arms:
            s = runs.get((t, a)); row.append("—" if not s else ("HF" if s["harness_failure"] else f"{s['Q']:.2f}" + ("" if s["Qbin"] else "✗") + ("⏱" if s["timed_out"] else "")))
        for a in arms:
            s = runs.get((t, a)); row.append("—" if not s else f"{s['tokens_total'] / 1000:.0f}")
        for a in arms:
            s = runs.get((t, a)); row.append("—" if not s or s.get("cost_usd") is None else f"{s['cost_usd']:.2f}")
        for a in arms:
            s = runs.get((t, a)); row.append("—" if not s else f"{len(s['skills'])}/{len(s['agents'])}")
        print("| " + " | ".join(row) + " |")
    print()
    tot = {a: {"usd": sum((runs[(t, a)].get("cost_usd") or 0) for t in tasks if (t, a) in runs),
               "ktok": sum(runs[(t, a)]["tokens_total"] for t in tasks if (t, a) in runs) / 1000,
               "wall_min": sum(runs[(t, a)]["wall_s"] for t in tasks if (t, a) in runs) / 60,
               "Qbin": sum(1 for t in tasks if (t, a) in runs and runs[(t, a)]["Qbin"]),
               "Qmean": statistics.mean([runs[(t, a)]["Q"] for t in tasks if (t, a) in runs]) if any((t, a) in runs for t in tasks) else None,
               "visible_ok": sum(1 for t in tasks if (t, a) in runs and (runs[(t, a)].get("visible_original") or {}).get("all_pass")),
               "timeouts": sum(1 for t in tasks if (t, a) in runs and runs[(t, a)]["timed_out"]),
               "no_edit": sum(1 for t in tasks if (t, a) in runs and not runs[(t, a)]["edited_any_file"]),
               "routing_blocks": sum(runs[(t, a)].get("acs_routing_blocks", 0) for t in tasks if (t, a) in runs),
               "ups_hook_kb": sum(runs[(t, a)].get("ups_hook_bytes", 0) for t in tasks if (t, a) in runs) / 1000}
           for a in arms}
    print("totals:", json.dumps({a: {k: (round(v, 2) if isinstance(v, float) else v) for k, v in d.items()} for a, d in tot.items()}))
    print()
    for x, y, label in (("A2", "A0", "PRIMARY"), ("A1", "A0", "secondary"), ("A2", "A1", "secondary")):
        print(f"{label} {x} vs {y}:", json.dumps(compare(runs, x, y, tasks)))
    sk = {}
    for (t, a), s in runs.items():
        for k in s["skills"]:
            sk[(a, k.split(":")[-1])] = sk.get((a, k.split(":")[-1]), 0) + 1
    print("\nskills invoked:", json.dumps({f"{a}:{k}": v for (a, k), v in sorted(sk.items())}))


if __name__ == "__main__":
    main()
