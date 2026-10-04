#!/usr/bin/env python3
"""Outcome-ablation runner (pre-registration R2). One invocation = one (model, task): the three
arms run concurrently in fresh HOMEs, then — after ALL arms have exited — the vault is unlocked,
each working copy is graded, and the vault is locked again.

usage: run.py <model> <task-id-dir> [arm ...]
Layout (ROOT = this file's dir):
  tasks/<task>/repo            what the subject sees (copied per run)
  vault/<task>/{hidden_tests,solution,wrong_fix,META.md}   mode 000 between gradings
  homes/<arm>                  HOME template per arm
  work/<model>/<task>/<arm>/{home,repo}    per-run, fresh
  runs/<model>/<task>/<arm>/{log.jsonl,err.txt,score.json}
A finished run (score.json present) is never overwritten, except one retry of a harness failure."""
import sys, os, json, shutil, subprocess, time, threading, signal

ROOT = os.path.dirname(os.path.abspath(__file__))
VAULT = os.path.join(ROOT, "vault")
SP = os.path.expanduser("~/.claude/plugins/cache/superpowers-marketplace/superpowers/6.4.2")
ACS = os.path.expanduser("~/.claude/plugins/cache/acsm/auto-claude-skills/3.93.1")
ARMS = {"A0": [], "A1": [SP], "A2": [SP, ACS]}
EXPECT = {"A0": (False, False), "A1": (True, False), "A2": (True, True)}  # (superpowers, acs) loaded
SUFFIX = ("\n\nYou are authorized to implement this directly; no design or plan approval is needed. "
          "No one is available to answer questions. Make reasonable assumptions, complete the task, and stop.")
# NOT A SANDBOX: unrestricted Bash as the invoking user, confined only by an isolated HOME and a scratch
# working copy. See the README security note before reusing this on anything but benign fixtures.
TOOLS = "Bash Read Edit Write MultiEdit Grep Glob Skill Agent Task TodoWrite NotebookEdit"
WALL_CAP = 20 * 60


def sh(cmd, cwd=None, timeout=120):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def grade(repo, tests):
    p = sh([sys.executable, os.path.join(ROOT, "hidden_runner.py"), repo, tests], timeout=300)
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:
        return {"all_pass": False, "run": 0, "failures": 0, "errors": 0, "load_error": "runner: " + (p.stderr or p.stdout)[-200:]}


def parse_log(path):
    d = {"init": None, "res": None, "skills": [], "agents": [], "tools": {}, "assistant_msgs": 0,
         "hook_bytes": {}, "acs_routing_blocks": 0, "sp_bootstrap": False}
    for line in open(path, errors="replace"):
        try:
            e = json.loads(line)
        except Exception:
            continue
        t, st = e.get("type"), e.get("subtype")
        if t == "system" and st == "init":
            d["init"] = {"plugins": sorted(p.get("name") for p in e.get("plugins", [])), "n_skills": len(e.get("skills", [])), "model": e.get("model")}
        elif t == "system" and st == "hook_response":
            out = e.get("stdout") or ""
            ev = str(e.get("hook_event") or e.get("hook_name") or "?").split(":")[0]
            d["hook_bytes"][ev] = d["hook_bytes"].get(ev, 0) + len(out.encode())
            if "SKILL ACTIVATION" in out:
                d["acs_routing_blocks"] += 1
            if "You have superpowers" in out:
                d["sp_bootstrap"] = True
        elif t == "assistant":
            d["assistant_msgs"] += 1
            for b in (e.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    n = b.get("name")
                    d["tools"][n] = d["tools"].get(n, 0) + 1
                    if n == "Skill":
                        d["skills"].append(str((b.get("input") or {}).get("skill", "")))
                    if n in ("Agent", "Task"):
                        d["agents"].append(str((b.get("input") or {}).get("subagent_type", "")))
        elif t == "result":
            d["res"] = e
    return d


def transcript_routing(home):
    """ACS's UserPromptSubmit output is not in the stream; read it from the run's own transcript."""
    import glob
    blocks = bytes_ = 0
    for f in glob.glob(os.path.join(home, ".claude", "projects", "*", "*.jsonl")):
        for line in open(f, errors="replace"):
            try:
                e = json.loads(line)
            except Exception:
                continue
            a = e.get("attachment") if isinstance(e, dict) else None
            if isinstance(a, dict) and a.get("type") == "hook_additional_context" and a.get("hookEvent") == "UserPromptSubmit":
                c = a.get("content")
                if isinstance(c, list):
                    c = "\n".join(x for x in c if isinstance(x, str))
                if isinstance(c, str):
                    bytes_ += len(c.encode())
                    if "SKILL ACTIVATION" in c:
                        blocks += 1
    return blocks, bytes_


def manipulation_ok(arm, d):
    if not d["init"]:
        return False, "no init event"
    pl = d["init"]["plugins"]
    want_sp, want_acs = EXPECT[arm]
    if ("superpowers" in pl) != want_sp or ("auto-claude-skills" in pl) != want_acs:
        return False, f"plugins {pl}"
    if d["sp_bootstrap"] != want_sp:
        return False, f"superpowers bootstrap present={d['sp_bootstrap']}"
    if not want_acs and d["acs_routing_blocks"]:
        return False, "ACS routing block in a non-ACS arm"
    return True, ""


def run_arm(model, task, arm, state):
    out = os.path.join(ROOT, "runs", model, task, arm)
    work = os.path.join(ROOT, "work", model, task, arm)
    retried = False
    if os.path.exists(os.path.join(out, "score.json")):
        prev = json.load(open(os.path.join(out, "score.json")))
        if not (prev.get("harness_failure") and not prev.get("retried")):
            state[arm] = None
            return
        retried = True
    shutil.rmtree(out, ignore_errors=True); shutil.rmtree(work, ignore_errors=True)
    os.makedirs(out); os.makedirs(work)
    repo, home = os.path.join(work, "repo"), os.path.join(work, "home")
    shutil.copytree(os.path.join(ROOT, "tasks", task, "repo"), repo)
    shutil.copytree(os.path.join(ROOT, "homes", arm), home, symlinks=True)
    sh(["git", "init", "-q", "."], cwd=repo); sh(["git", "add", "-A"], cwd=repo)
    sh(["git", "-c", "user.name=base", "-c", "user.email=base@example.invalid", "commit", "-q", "-m", "baseline"], cwd=repo)
    base = sh(["git", "rev-parse", "HEAD"], cwd=repo).stdout.strip()
    prompt = open(os.path.join(repo, "TASK.md")).read() + SUFFIX
    env = dict(os.environ, HOME=home, PUSH_GATE_CAPTURE_DISABLE="1",
               IMPLEMENT_SHADOW_LOG=os.path.join(work, "shadow-impl.jsonl"),
               REVIEW_SHADOW_LOG=os.path.join(work, "shadow-review.jsonl"),
               VERIFY_SHADOW_LOG=os.path.join(work, "shadow-verify.jsonl"))
    for k in list(env):
        if k.startswith("CLAUDE") or k in ("ANTHROPIC_MODEL",):
            env.pop(k, None)
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "stream-json", "--verbose",
           "--setting-sources", "project", "--strict-mcp-config", "--max-budget-usd", "4",
           "--permission-mode", "acceptEdits", "--allowedTools", TOOLS]
    for p in ARMS[arm]:
        cmd += ["--plugin-dir", p]
    t0 = time.time(); timed_out = False
    with open(os.path.join(out, "log.jsonl"), "w") as lo, open(os.path.join(out, "err.txt"), "w") as le:
        proc = subprocess.Popen(cmd, cwd=repo, env=env, stdin=subprocess.DEVNULL, stdout=lo, stderr=le, start_new_session=True)
        try:
            rc = proc.wait(timeout=WALL_CAP)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except Exception:
                pass
            rc = -15
    wall = time.time() - t0
    for pid in sh(["pgrep", "-f", "cozempic.cli guard --cwd " + repo]).stdout.split():
        try:
            os.kill(int(pid), signal.SIGTERM)  # only the guard daemon this run's ACS session started
        except Exception:
            pass
    state[arm] = {"base": base, "out": out, "repo": repo, "rc": rc, "timed_out": timed_out, "wall": wall, "retried": retried}


def finish(model, task, arm, st):
    d = parse_log(os.path.join(st["out"], "log.jsonl"))
    d["acs_routing_blocks"], d["ups_hook_bytes"] = transcript_routing(os.path.join(os.path.dirname(st["repo"]), "home"))
    res = d["res"] or {}
    ok, why = manipulation_ok(arm, d)
    repo = st["repo"]
    sh(["git", "add", "-A", "-N"], cwd=repo)
    added = removed = files = 0
    for ln in sh(["git", "diff", "--numstat", st["base"]], cwd=repo).stdout.splitlines():
        parts = ln.split("\t")
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            added += int(parts[0]); removed += int(parts[1]); files += 1
    hidden = grade(repo, os.path.join(VAULT, task, "hidden_tests"))
    visible = grade(repo, os.path.join(ROOT, "tasks", task, "repo", "tests"))  # ORIGINAL visible tests
    mu = res.get("modelUsage") or {}
    tok = {"input": 0, "cache_create": 0, "cache_read": 0, "output": 0}
    for m in mu.values():
        tok["input"] += m.get("inputTokens", 0) or 0
        tok["cache_create"] += m.get("cacheCreationInputTokens", 0) or 0
        tok["cache_read"] += m.get("cacheReadInputTokens", 0) or 0
        tok["output"] += m.get("outputTokens", 0) or 0
    q = (hidden.get("run", 0) - hidden.get("failures", 0) - hidden.get("errors", 0)) / hidden["run"] if hidden.get("run") and not hidden.get("load_error") else 0.0
    score = {
        "model_asked": model, "task": task, "arm": arm, "rc": st["rc"], "timed_out": st["timed_out"], "wall_s": round(st["wall"], 1),
        "retried": st["retried"], "init": d["init"], "manipulation_ok": ok, "manipulation_note": why,
        "harness_failure": bool(d["assistant_msgs"] == 0 or not ok),
        "is_error": res.get("is_error"), "result_subtype": res.get("subtype"), "cost_usd": res.get("total_cost_usd"),
        "num_turns": res.get("num_turns"), "models_used": sorted(mu.keys()), "tokens": tok, "tokens_total": sum(tok.values()),
        "hook_bytes": d["hook_bytes"], "acs_routing_blocks": d["acs_routing_blocks"], "ups_hook_bytes": d["ups_hook_bytes"], "skills": d["skills"], "agents": d["agents"], "tools": d["tools"],
        "diff": {"files": files, "added": added, "removed": removed}, "edited_any_file": files > 0,
        "hidden": hidden, "Q": round(q, 4), "Qbin": bool(hidden.get("all_pass")), "visible_original": visible,
    }
    json.dump(score, open(os.path.join(st["out"], "score.json"), "w"), indent=1)
    return (f"{model} {task} {arm}: Q={score['Q']} bin={score['Qbin']} ({hidden.get('run')}run) tokens={score['tokens_total']} "
            f"usd={score['cost_usd']} wall={score['wall_s']}s turns={score['num_turns']} skills={len(d['skills'])} agents={len(d['agents'])} "
            f"manip={'ok' if ok else 'FAIL ' + why}{' HARNESS_FAILURE' if score['harness_failure'] else ''}{' TIMEOUT' if st['timed_out'] else ''}")


def main():
    model, task = sys.argv[1], sys.argv[2]
    arms = sys.argv[3:] or list(ARMS)
    os.chmod(VAULT, 0o000)  # locked while any subject runs
    state, th = {}, []
    for a in arms:
        t = threading.Thread(target=run_arm, args=(model, task, a, state)); t.start(); th.append(t)
    for t in th:
        t.join()
    os.chmod(VAULT, 0o700)
    try:
        for a in arms:
            print(finish(model, task, a, state[a]) if state.get(a) else f"{model} {task} {a}: skipped (already scored)")
    finally:
        os.chmod(VAULT, 0o000)


if __name__ == "__main__":
    main()
