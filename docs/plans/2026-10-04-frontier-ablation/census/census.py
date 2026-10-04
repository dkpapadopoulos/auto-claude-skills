#!/usr/bin/env python3
"""Phase-0 usage census over local Claude Code transcripts. Aggregate counts only;
no prompt text is written anywhere.

Unit: a ROUTING EVENT = one UserPromptSubmit hook_additional_context attachment carrying a
"SKILL ACTIVATION" block. Its WINDOW runs until the next input entry in that session file.
UPTAKE of a routed skill = a `Skill` tool_use naming it inside the window.
"""
import sys, os, json, glob, re, collections, statistics

sys.dont_write_bytecode = True
PROBE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "tests", "probes", "real-prompt-replay")
sys.path.insert(0, PROBE)
from routed import input_kind  # noqa: E402

ROLE_LINE = re.compile(r"^([A-Z][A-Za-z ]*): ([a-z0-9][a-z0-9-]*) -> Skill\(([^)]+)\)", re.M)
MUST = re.compile(r"\| ([a-z0-9][a-z0-9-]*) MUST INVOKE")
STEP = re.compile(r"^\s*\[(CURRENT|NEXT|LATER|DONE)\] Step \d+: Skill\(([^)]+)\)", re.M)
HINT = re.compile(r"^- ([A-Z][A-Z0-9 →>/&'-]{3,60}):", re.M)


def short(name):
    return name.split(":")[-1].strip()


def fam(model):
    if not model:
        return "unknown"
    m = model.lower()
    for k in ("fable", "mythos", "opus-5-5", "opus-5", "opus-4", "sonnet-5-5", "sonnet-5", "sonnet-4", "haiku"):
        if k in m:
            return k
    return m[:24]


def main():
    since = sys.argv[1] if len(sys.argv) > 1 else "2026-08-01"
    files = glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))
    events = []  # dicts
    unrouted_inv = collections.Counter()
    sess_models = collections.Counter()
    dup = 0
    n_files = 0
    first_ts, last_ts = None, None
    for f in files:
        cur = None
        seen_keys = set()
        file_models = collections.Counter()
        last_src = ""
        used = False
        try:
            fh = open(f, errors="replace")
        except OSError:
            continue
        for line in fh:
            try:
                e = json.loads(line)
            except Exception:
                continue
            if not isinstance(e, dict) or e.get("isSidechain"):
                continue
            ts = e.get("timestamp") or ""
            if ts and ts[:10] < since:
                continue
            kind = input_kind(e)
            a = e.get("attachment")
            is_tool_result = False
            if e.get("type") == "user":
                c = (e.get("message") or {}).get("content")
                if isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                    is_tool_result = True
            if kind and not is_tool_result:
                last_src = kind
                cur = None  # window closes at the next input
            if isinstance(a, dict) and a.get("type") == "hook_additional_context" and a.get("hookEvent") == "UserPromptSubmit":
                c = a.get("content")
                if isinstance(c, list):
                    c = "\n".join(x for x in c if isinstance(x, str))
                if isinstance(c, str) and "SKILL ACTIVATION" in c:
                    key = (e.get("parentUuid"), hash(c))
                    if key in seen_keys:
                        dup += 1
                        continue
                    seen_keys.add(key)
                    routed = [(m.group(1), short(m.group(3))) for m in ROLE_LINE.finditer(c)]
                    must = set(MUST.findall(c))
                    cur = {
                        "bytes": len(c.encode()),
                        "routed": routed,
                        "must": must,
                        "current_step": [short(m.group(2)) for m in STEP.finditer(c) if m.group(1) == "CURRENT"],
                        "hints": HINT.findall(c),
                        "invoked": [],
                        "model": None,
                        "src": last_src,
                        "ts": ts,
                    }
                    events.append(cur)
                    used = True
                    first_ts = ts if first_ts is None or ts < first_ts else first_ts
                    last_ts = ts if last_ts is None or ts > last_ts else last_ts
            if e.get("type") == "assistant":
                msg = e.get("message") or {}
                model = msg.get("model")
                if model and model != "<synthetic>":
                    file_models[fam(model)] += 1
                    if cur is not None and cur["model"] is None:
                        cur["model"] = fam(model)
                for b in msg.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill":
                        s = short(str((b.get("input") or {}).get("skill", "")))
                        if cur is not None:
                            cur["invoked"].append(s)
                            if s not in {r[1] for r in cur["routed"]}:
                                unrouted_inv[s] += 1
                        else:
                            unrouted_inv[s] += 1
        fh.close()
        if file_models:
            n_files += 1
            sess_models[file_models.most_common(1)[0][0]] += 1

    out = {}
    out["window"] = {"since": since, "first_routing": first_ts, "last_routing": last_ts,
                     "session_files_with_assistant_turns": n_files, "routing_events": len(events),
                     "duplicate_attachments_dropped": dup}
    out["sessions_by_dominant_model"] = dict(sess_models.most_common())
    out["routing_events_by_source"] = dict(collections.Counter(ev["src"] or "none" for ev in events).most_common())
    out["routing_events_by_model"] = dict(collections.Counter(ev["model"] or "no-assistant-turn" for ev in events).most_common())

    def table(evs):
        routed = collections.Counter(); taken = collections.Counter()
        must_n = collections.Counter(); must_taken = collections.Counter()
        for ev in evs:
            inv = set(ev["invoked"])
            for _role, s in ev["routed"]:
                routed[s] += 1
                if s in inv:
                    taken[s] += 1
                if s in ev["must"]:
                    must_n[s] += 1
                    if s in inv:
                        must_taken[s] += 1
        rows = []
        for s, n in routed.most_common():
            rows.append({"skill": s, "routed": n, "invoked_in_window": taken[s],
                         "must_invoke": must_n[s], "must_invoked": must_taken[s]})
        tot = {"routed": sum(routed.values()), "invoked": sum(taken.values()),
               "must": sum(must_n.values()), "must_invoked": sum(must_taken.values()),
               "events": len(evs), "events_with_any_skill_call": sum(1 for ev in evs if ev["invoked"]),
               "events_with_any_routed_skill_call": sum(1 for ev in evs if set(ev["invoked"]) & {r[1] for r in ev["routed"]})}
        return rows, tot

    human = [ev for ev in events if ev["src"] == "human"]
    out["human_events"] = len(human)
    rows, tot = table(human)
    out["uptake_human_all_models"] = {"totals": tot, "rows": rows}
    for fam_name in ("fable", "opus-5-5", "opus-5", "opus-4", "sonnet-5-5", "sonnet-5", "haiku"):
        evs = [ev for ev in human if ev["model"] == fam_name]
        if evs:
            r, t = table(evs)
            out["uptake_human_" + fam_name] = {"totals": t, "rows": r[:40]}
    b = [ev["bytes"] for ev in human]
    if b:
        b.sort()
        out["injected_bytes_human"] = {"n": len(b), "sum": sum(b), "median": statistics.median(b),
                                       "p90": b[int(len(b) * 0.9) - 1], "max": b[-1], "mean": round(sum(b) / len(b))}
    hints = collections.Counter()
    for ev in human:
        for h in set(ev["hints"]):
            hints[h] += 1
    out["hint_labels_human"] = dict(hints.most_common(40))
    out["skill_calls_not_routed_that_turn"] = dict(unrouted_inv.most_common(40))
    json.dump(out, sys.stdout, indent=1)


if __name__ == "__main__":
    main()
