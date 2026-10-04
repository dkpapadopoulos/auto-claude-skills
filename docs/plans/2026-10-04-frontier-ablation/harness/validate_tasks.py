#!/usr/bin/env python3
"""Fixture validity gate, legs 1-5 of pre-registration R2 (leg 6 is a recorded human/agent review).
usage: validate_tasks.py <authoring_tasks_dir>   -> prints one line per task; writes gate.json beside this file."""
import sys, os, json, shutil, subprocess, tempfile, hashlib

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.abspath(sys.argv[1])


def grade(repo, tests):
    p = subprocess.run([sys.executable, os.path.join(ROOT, "hidden_runner.py"), repo, tests], capture_output=True, text=True, timeout=180)
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:
        return {"all_pass": False, "run": 0, "failures": 0, "errors": 0, "load_error": "runner: " + (p.stderr or p.stdout)[-200:]}


def tree_hash(d):
    h = hashlib.sha256()
    for dp, dn, fs in os.walk(d):
        dn[:] = sorted(x for x in dn if x != "__pycache__")
        for f in sorted(fs):
            if f.endswith(".pyc"):
                continue
            p = os.path.join(dp, f); h.update(os.path.relpath(p, d).encode()); h.update(b"\0"); h.update(open(p, "rb").read())
    return h.hexdigest()


def blobs(d):
    out = {}
    for dp, dn, fs in os.walk(d):
        dn[:] = [x for x in dn if x != "__pycache__"]
        for f in fs:
            if not f.endswith(".pyc"):
                out[os.path.relpath(os.path.join(dp, f), d)] = open(os.path.join(dp, f), "rb").read()
    return out


gate = {}
for t in sorted(os.listdir(SRC)):
    d = os.path.join(SRC, t)
    if not os.path.isdir(d):
        continue
    repo, hid, sol, wrong = (os.path.join(d, x) for x in ("repo", "hidden_tests", "solution", "wrong_fix"))
    legs, notes = {}, []
    if not all(os.path.isdir(x) for x in (repo, hid, sol, wrong)) or not os.path.isdir(os.path.join(repo, "tests")):
        gate[t] = {"pass": False, "legs": {"layout": False}, "notes": ["missing directory"]}
        print("FAIL", t, "layout"); continue
    with tempfile.TemporaryDirectory() as tmp:
        start = os.path.join(tmp, "start"); shutil.copytree(repo, start)
        solved = os.path.join(tmp, "solved"); shutil.copytree(repo, solved); shutil.copytree(sol, solved, dirs_exist_ok=True)
        wrongd = os.path.join(tmp, "wrong"); shutil.copytree(repo, wrongd); shutil.copytree(wrong, wrongd, dirs_exist_ok=True)
        vis = os.path.join(repo, "tests")  # ORIGINAL visible tests, as the grader uses them
        h_start, h_sol, h_wrong = grade(start, hid), grade(solved, hid), grade(wrongd, hid)
        v_start, v_sol, v_wrong = grade(start, vis), grade(solved, vis), grade(wrongd, vis)
    legs["1_hidden_red_on_start"] = (not h_start["all_pass"]) and h_start.get("run", 0) > 0 and not h_start.get("load_error")
    legs["2_hidden_green_with_solution"] = h_sol["all_pass"]
    legs["3_visible_runs_and_green_with_solution"] = v_start.get("run", 0) > 0 and not v_start.get("load_error") and v_sol["all_pass"]
    legs["4_wrong_fix_passes_visible_fails_hidden"] = v_wrong["all_pass"] and (not h_wrong["all_pass"]) and h_wrong.get("run", 0) > 0 and not h_wrong.get("load_error")
    rb, hb, sb, wb = blobs(repo), blobs(hid), blobs(sol), blobs(wrong)
    leak = []
    for name, content in hb.items():
        if any(content == c for c in rb.values()):
            leak.append("hidden identical to repo file: " + name)
        if any(os.path.basename(n) == os.path.basename(name) for n in rb):
            leak.append("hidden name collides: " + name)
    if not sb:
        leak.append("empty solution")
    if all(rb.get(n) == c for n, c in sb.items()):
        leak.append("solution identical to start")
    if not wb or all(rb.get(n) == c for n, c in wb.items()):
        leak.append("wrong_fix empty or identical to start")
    if sb and wb and sb == wb:
        leak.append("wrong_fix identical to solution")
    tm = rb.get("TASK.md", b"").decode(errors="replace").lower()
    if not tm:
        leak.append("no TASK.md")
    for w in ("hidden", "grader", "wrong_fix", "trap"):
        if w in tm:
            leak.append("TASK.md mentions " + w)
    if not os.path.isfile(os.path.join(d, "META.md")):
        leak.append("no META.md")
    legs["5_no_leak"] = not leak
    src_lines = sum(c.count(b"\n") for n, c in rb.items() if n.endswith(".py") and not n.startswith("tests"))
    ok = all(legs.values())
    gate[t] = {"pass": ok, "legs": legs, "notes": leak, "hidden_tests": h_sol.get("run"), "hidden_fail_on_start": h_start.get("failures", 0) + h_start.get("errors", 0),
               "hidden_fail_with_wrong_fix": h_wrong.get("failures", 0) + h_wrong.get("errors", 0), "visible_tests": v_start.get("run"),
               "visible_fail_on_start": v_start.get("failures", 0) + v_start.get("errors", 0), "src_lines": src_lines, "sha256": tree_hash(d)}
    print(("PASS " if ok else "FAIL ") + t, {k: v for k, v in legs.items() if not v} or "", f"hidden={h_sol.get('run')} red={gate[t]['hidden_fail_on_start']} wrongfix_red={gate[t]['hidden_fail_with_wrong_fix']} visible={v_start.get('run')}(start_fail={gate[t]['visible_fail_on_start']}) src_lines={src_lines}", leak or "")
json.dump(gate, open(os.path.join(ROOT, "gate.json"), "w"), indent=1, sort_keys=True)
n_ok = sum(1 for g in gate.values() if g["pass"])
print(f"{n_ok}/{len(gate)} tasks pass legs 1-5")
