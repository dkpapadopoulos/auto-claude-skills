#!/usr/bin/env python3
"""Session-level uptake: for each (session, skill) with a MUST INVOKE routing on a human prompt,
was the skill invoked (a) in the same turn window, (b) later in the session, (c) already loaded
EARLIER in the session (so re-invocation is not needed), (d) never. Counts only."""
import sys, os, json, glob, re, collections
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "tests", "probes", "real-prompt-replay"))
from routed import input_kind
ROLE_LINE = re.compile(r"^([A-Z][A-Za-z ]*): ([a-z0-9][a-z0-9-]*) -> Skill\(([^)]+)\)", re.M)
MUST = re.compile(r"\| ([a-z0-9][a-z0-9-]*) MUST INVOKE")
short = lambda n: n.split(":")[-1].strip()
def fam(m):
    m=(m or "").lower()
    for k in ("fable","mythos","opus-5-5","opus-5","opus-4","sonnet-5-5","sonnet-5","sonnet-4","haiku"):
        if k in m: return k
    return "unknown"
since = sys.argv[1]
pairs = collections.Counter()      # (model, skill, outcome)
ev_zero_parse = 0; ev_total = 0
reviewer_dispatch = collections.Counter()
for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
    seq = []  # ordered items: ("in",src) ("route",must,routed) ("skill",name) ("agent",type) ("model",fam)
    for line in open(f, errors="replace"):
        try: e = json.loads(line)
        except Exception: continue
        if not isinstance(e, dict) or e.get("isSidechain"): continue
        ts = e.get("timestamp") or ""
        if ts and ts[:10] < since: continue
        kind = input_kind(e)
        tr = False
        if e.get("type") == "user":
            c = (e.get("message") or {}).get("content")
            tr = isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)
        if kind and not tr: seq.append(("in", kind))
        a = e.get("attachment")
        if isinstance(a, dict) and a.get("type") == "hook_additional_context" and a.get("hookEvent") == "UserPromptSubmit":
            c = a.get("content")
            if isinstance(c, list): c = "\n".join(x for x in c if isinstance(x, str))
            if isinstance(c, str) and "SKILL ACTIVATION" in c:
                routed = {short(m.group(3)) for m in ROLE_LINE.finditer(c)}
                seq.append(("route", set(MUST.findall(c)), routed))
        if e.get("type") == "assistant":
            msg = e.get("message") or {}
            if msg.get("model") and msg.get("model") != "<synthetic>": seq.append(("model", fam(msg["model"])))
            for b in msg.get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    if b.get("name") == "Skill": seq.append(("skill", short(str((b.get("input") or {}).get("skill", "")))))
                    if b.get("name") in ("Agent", "Task"): seq.append(("agent", str((b.get("input") or {}).get("subagent_type", ""))))
    # walk
    first_seen = {}   # skill -> index of first human MUST routing
    src = ""
    for i, it in enumerate(seq):
        if it[0] == "in": src = it[1]
        if it[0] == "route" and src == "human":
            ev_total += 1
            if not it[2]: ev_zero_parse += 1
            for s in it[1]:
                first_seen.setdefault(s, i)
    for s, i in first_seen.items():
        model = next((x[1] for x in seq[i:] if x[0] == "model"), "none")
        before = any(x[0] == "skill" and x[1] == s for x in seq[:i])
        # window = until next "in"
        j = next((k for k in range(i + 1, len(seq)) if seq[k][0] == "in"), len(seq))
        inwin = any(x[0] == "skill" and x[1] == s for x in seq[i:j])
        later = any(x[0] == "skill" and x[1] == s for x in seq[j:])
        out = "same_turn" if inwin else "later_in_session" if later else "loaded_earlier" if before else "never"
        pairs[(model, s, out)] += 1
        if s == "requesting-code-review":
            disp = any(x[0] == "agent" and "review" in x[1].lower() for x in seq[i:])
            reviewer_dispatch[(model, out, "reviewer_agent_dispatched" if disp else "no_reviewer_agent")] += 1
print(json.dumps({"human_routing_events": ev_total, "events_with_no_parsed_role_line": ev_zero_parse}))
models = sorted({k[0] for k in pairs})
skills = sorted({k[1] for k in pairs}, key=lambda s: -sum(v for k, v in pairs.items() if k[1] == s))
outs = ["same_turn", "later_in_session", "loaded_earlier", "never"]
print("\nSESSION-LEVEL (first MUST-INVOKE routing of a skill per session), all models")
print(f"{'skill':34}" + "".join(f"{o:>18}" for o in outs) + f"{'n':>6}")
tot = collections.Counter()
for s in skills:
    row = [sum(v for k, v in pairs.items() if k[1] == s and k[2] == o) for o in outs]
    for o, v in zip(outs, row): tot[o] += v
    print(f"{s:34}" + "".join(f"{v:>18}" for v in row) + f"{sum(row):>6}")
print(f"{'TOTAL':34}" + "".join(f"{tot[o]:>18}" for o in outs) + f"{sum(tot.values()):>6}")
print("\nBY MODEL (all skills)")
for m in models:
    row = [sum(v for k, v in pairs.items() if k[0] == m and k[2] == o) for o in outs]
    print(f"{m:34}" + "".join(f"{v:>18}" for v in row) + f"{sum(row):>6}")
print("\nrequesting-code-review: was a reviewer subagent dispatched anyway?")
for k, v in sorted(reviewer_dispatch.items()): print(" ", k, v)
