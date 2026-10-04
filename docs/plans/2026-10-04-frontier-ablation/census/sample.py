#!/usr/bin/env python3
"""Write a BLIND labelling sample (id, prompt, skill) and a separate key (id, outcome, model).
Both files are private (0600) and stay in the scratchpad; prompt text never leaves it."""
import sys, os, json, glob, re, random, collections
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "tests", "probes", "real-prompt-replay"))
from routed import input_kind
from extract import prompt_of, open_private
MUST = re.compile(r"\| ([a-z0-9][a-z0-9-]*) MUST INVOKE")
short = lambda n: n.split(":")[-1].strip()
def fam(m):
    m=(m or "").lower()
    for k in ("fable","opus-5-5","opus-5","opus-4","sonnet-5-5","sonnet-5","haiku"):
        if k in m: return k
    return "unknown"
since = sys.argv[1]; rows = []
for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
    seq = []
    for line in open(f, errors="replace"):
        try: e = json.loads(line)
        except Exception: continue
        if not isinstance(e, dict) or e.get("isSidechain"): continue
        ts = e.get("timestamp") or ""
        if ts and ts[:10] < since: continue
        kind = input_kind(e); tr = False
        if e.get("type") == "user":
            c = (e.get("message") or {}).get("content")
            tr = isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)
        if kind and not tr:
            p = prompt_of(e)
            seq.append(("in", kind, p[0] if p else ""))
        a = e.get("attachment")
        if isinstance(a, dict) and a.get("type") == "hook_additional_context" and a.get("hookEvent") == "UserPromptSubmit":
            c = a.get("content")
            if isinstance(c, list): c = "\n".join(x for x in c if isinstance(x, str))
            if isinstance(c, str) and "SKILL ACTIVATION" in c: seq.append(("route", set(MUST.findall(c))))
        if e.get("type") == "assistant":
            msg = e.get("message") or {}
            if msg.get("model") and msg["model"] != "<synthetic>": seq.append(("model", fam(msg["model"])))
            for b in msg.get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill":
                    seq.append(("skill", short(str((b.get("input") or {}).get("skill", "")))))
    first = {}; src = ""; txt = ""; nprev = 0
    for i, it in enumerate(seq):
        if it[0] == "in":
            src, txt = it[1], it[2]
            if src == "human": nprev += 1
        if it[0] == "route" and src == "human":
            for s in it[1]: first.setdefault(s, (i, txt, nprev))
    for s, (i, txt, nprev) in first.items():
        j = next((k for k in range(i + 1, len(seq)) if seq[k][0] == "in"), len(seq))
        inwin = any(x[0] == "skill" and x[1] == s for x in seq[i:j])
        later = any(x[0] == "skill" and x[1] == s for x in seq[j:])
        before = any(x[0] == "skill" and x[1] == s for x in seq[:i])
        out = "same_turn" if inwin else "later" if later else "loaded_earlier" if before else "never"
        model = next((x[1] for x in seq[i:] if x[0] == "model"), "none")
        rows.append({"prompt": txt[:1500], "prompt_chars": len(txt), "skill": s, "outcome": out, "model": model,
                     "human_turn_index": nprev, "project": os.path.basename(os.path.dirname(f))[-24:]})
random.Random(20261004).shuffle(rows)
with open_private("label_sample.jsonl") as a, open_private("label_key.jsonl") as b:
    for n, r in enumerate(rows):
        rid = f"r{n:03d}"
        a.write(json.dumps({"id": rid, "skill": r["skill"], "human_turn_index_in_session": r["human_turn_index"], "prompt": r["prompt"]}) + "\n")
        b.write(json.dumps({"id": rid, "skill": r["skill"], "outcome": r["outcome"], "model": r["model"], "project": r["project"], "prompt_chars": r["prompt_chars"]}) + "\n")
empty = sum(1 for r in rows if not r["prompt"])
L = sorted(r["prompt_chars"] for r in rows)
print("rows", len(rows), "empty_prompt", empty, "median_chars", L[len(L)//2], "p90", L[int(len(L)*0.9)])
