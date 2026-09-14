#!/usr/bin/env python3
"""Native contract conformance against the DEPLOYED ACS plugin with live hooks.

Conformance, not comparison: each case asks one yes/no question about what the
system does when asked, and retains the trace. No arms, no scores, no judges.

Dispatch policy, which is the safety design and not an incidental flag choice:
`Skill` and `Read` are allowlisted so a consultation INVOCATION is observable;
`Agent`, `Task` and `Bash` are not, so the invoked skill cannot actually dispatch to
another model. Installation is not authorization. The invocation is the observable;
the outbound call is never performed.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

def _repo_root(start):
    """Walk up to the repository root by MARKER, not by counting directories.

    The audit originals hard-coded a parent index, which silently resolved to the
    wrong directory when this package was ported -- and, worse, one of them happened
    to resolve correctly at the new depth, so it would have kept working until
    someone moved the file again."""
    for candidate in [start, *start.parents]:
        if ((candidate / ".claude-plugin" / "plugin.json").is_file()
                and (candidate / "config" / "default-triggers.json").is_file()):
            return candidate
    raise SystemExit(f"repository root not found above {start}")


HERE = Path(__file__).resolve().parent
ACS = _repo_root(HERE)
CLI = "/opt/homebrew/bin/claude"
MODEL = "claude-sonnet-5"
TOOLS = "Skill,Read"
TIMEOUT = 300

CONSULTATION = ("panel", "synthesize", "design-debate")

# An absence is only informative if the thing absent COULD have happened.
# A2 and B2 recorded "did not synthesize" while no perspectives existed to
# synthesize -- dispatch was withheld, so the absence carried no information.
# Keyed by bare skill name; a skill not listed here has no declared
# precondition and its absence is taken as informative.
ABSENCE_PRECONDITION = {
    "synthesize": lambda parsed: parsed["subagent_dispatches"] > 0,
}


def sha256_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_stream(path):
    """Positive classification from the retained stream."""
    events = []
    for line in path.read_text().splitlines():
        if line.strip():
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    skills, tools, denials, models = [], [], [], set()
    pending, results = {}, {}
    init = None
    for event in events:
        if event.get("type") == "system" and event.get("subtype") == "init":
            init = event
        if event.get("type") == "assistant":
            message = event.get("message", {})
            if message.get("model"):
                models.add(message["model"])
            for block in message.get("content", []):
                if block.get("type") == "tool_use":
                    tools.append(block["name"])
                    if block["name"] == "Skill":
                        name = str(block.get("input", {}).get("skill", ""))
                        skills.append(name)
                        pending[block["id"]] = name
        if event.get("type") == "user":
            for block in (event.get("message", {}).get("content") or []):
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    content = block.get("content")
                    text = content if isinstance(content, str) else " ".join(
                        part.get("text", "") for part in content if isinstance(part, dict))
                    if block.get("tool_use_id") in pending:
                        results[block["tool_use_id"]] = text
                    if "denied" in text.lower() or "permission" in text.lower():
                        denials.append(text[:200])

    # An ATTEMPTED skill call is not an invocation. A refused call carries a
    # tool_use_error; counting it as present reports a blocked path as conformance,
    # which is exactly how this classifier was wrong on its first run.
    outcomes = {}
    for identifier, name in pending.items():
        text = results.get(identifier, "")
        lowered = text.lower()
        if "disable-model-invocation" in lowered or "cannot be used with skill tool" in lowered:
            outcomes[name] = "refused_disable_model_invocation"
        elif "tool_use_error" in lowered or "is_error" in lowered:
            outcomes[name] = "error"
        elif not text:
            outcomes[name] = "no_result"
        else:
            outcomes[name] = "succeeded"
    # A second call to the same skill overwrites the first in `outcomes`,
    # which is keyed by NAME. Record the repetition before it disappears:
    # duplicate successful calls can otherwise produce a false conclusion.
    bare = [s.split(":")[-1] for s in skills if s]
    duplicates = sorted({name for name in bare if bare.count(name) > 1})
    unmatched = sorted(set(results) - set(pending))
    dispatched = [t for t in tools if t in ("Agent", "Task")]
    result = [e for e in events if e.get("type") == "result"]
    return {
        "events": len(events),
        "init_model": (init or {}).get("model"),
        "assistant_models": sorted(models),
        "skills_attempted": skills,
        "skill_outcomes": {k.split(":")[-1]: v for k, v in outcomes.items()},
        "skills_succeeded": sorted({k.split(":")[-1] for k, v in outcomes.items()
                                    if v == "succeeded"}),
        "skills_refused": sorted({k.split(":")[-1] for k, v in outcomes.items()
                                  if v.startswith("refused")}),
        "skills_bare": sorted(set(bare)),
        "duplicate_skill_calls": duplicates,
        "unmatched_results": unmatched,
        "tools_used": sorted(set(tools)),
        "subagent_dispatches": len(dispatched),
        "tool_denials": denials,
        "result_subtype": result[0].get("subtype") if result else None,
        "is_error": result[0].get("is_error") if result else None,
        "cost_usd": result[0].get("total_cost_usd") if result else None,
        "final_text": (result[0].get("result") or "")[:1500] if result else "",
    }


def judge(case, parsed):
    """Compare the observation against the case's frozen contract."""
    # Expectations are judged on SUCCEEDED calls, never on attempts.
    invoked = set(parsed["skills_succeeded"])

    # A run that did not complete cleanly is UNSCORED, not clean. Pooling it with
    # conformant runs scores whatever landed before the provider cut the run off;
    # the r4 trace carries subtype "success" with is_error true and a session
    # limit, so subtype alone is not enough to tell.
    if parsed["is_error"] or parsed["result_subtype"] != "success":
        disposition = "unscored_provider_error"
    elif parsed["duplicate_skill_calls"]:
        disposition = "inconclusive_duplicate_calls"
    elif parsed["unmatched_results"]:
        disposition = "inconclusive_unmatched_results"
    else:
        disposition = "scored"

    violations = []
    for name in case.get("expect_present", []):
        if name not in invoked:
            violations.append(f"expected present: {name}")
    for name in case.get("expect_absent", []):
        if name in invoked:
            violations.append(f"expected absent: {name}")
    consulted = sorted(invoked & set(CONSULTATION))
    uninformative = sorted(
        name for name in case.get("expect_absent", [])
        if name in ABSENCE_PRECONDITION and not ABSENCE_PRECONDITION[name](parsed))
    return {
        "disposition": disposition,
        "uninformative_absences": uninformative,
        "consultation_skills_succeeded": consulted,
        "consultation_skills_attempted": sorted(set(parsed["skills_bare"]) & set(CONSULTATION)),
        # Only a scored run can be satisfied. An unscored or inconclusive run
        # is never a pass, however few violations it happens to show.
        "satisfied": disposition == "scored" and not violations,
        "violations": violations,
        # A case whose only expectations are absences, met by invoking nothing at
        # all, is satisfied trivially. Say so rather than counting it as conformance.
        "vacuous": (not violations and not invoked
                    and not case.get("expect_present")),
    }


def exit_code(records):
    """Non-zero when any case is unsatisfied or could not be scored.

    The runner is paid and non-deterministic and must not be wired to a gate --
    but an instrument that reports a violation and exits 0 cannot be wired to one
    safely either.
    """
    for record in records:
        # `--out` without `--live` prepares manifests and scores nothing. Such a
        # record carries no disposition, and calling that a failure would make
        # preparing a run report as a failing one.
        if record.get("prepared_only"):
            continue
        if record.get("disposition") != "scored" or not record.get("satisfied"):
            return 1
    return 0


def run_case(case, out, live):
    directory = out / case["id"]
    directory.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="acs-conformance-") as temporary:
        cwd = Path(temporary) / "workspace"
        cwd.mkdir()
        settings = {"enabledPlugins": {}, "permissions": {"deny": []}}
        config = Path(temporary) / "settings.json"
        config.write_text(json.dumps(settings))
        tools = case.get("tools", TOOLS)
        command = [CLI, "--print", "--verbose", "--output-format", "stream-json",
                   "--model", MODEL, "--setting-sources", "", "--settings", str(config),
                   "--plugin-dir", str(ACS),
                   "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
                   "--tools", tools, "--allowedTools", tools,
                   "--permission-mode", "dontAsk", "--no-chrome",
                   "--no-session-persistence", "--max-budget-usd", "2"]
        manifest = {"case": case["id"], "contract": case["contract"],
                    "prompt": case["prompt"], "command": command, "cwd": str(cwd),
                    "acs_root": str(ACS), "model": MODEL,
                    "tools": tools,
                    "dispatch_policy": case.get("dispatch_policy",
                        "Skill/Read allowlisted; Agent/Task/Bash withheld"),
                    "hooks": "LIVE — the deployed plugin's own hooks are active"}
        (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if not live:
            return {"case": case["id"], "prepared_only": True}
        started = time.monotonic()
        with (directory / "stdout.jsonl").open("w") as stdout, \
             (directory / "stderr.txt").open("w") as stderr:
            process = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE,
                                       stdout=stdout, stderr=stderr, text=True,
                                       start_new_session=True)
            timed_out = False
            try:
                process.communicate(case["prompt"], timeout=TIMEOUT)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
        elapsed = time.monotonic() - started
    parsed = parse_stream(directory / "stdout.jsonl")
    verdict = judge(case, parsed)
    record = {"case": case["id"], "contract": case["contract"],
              "returncode": process.returncode, "timed_out": timed_out,
              "elapsed_seconds": round(elapsed, 1), **parsed, **verdict}
    (directory / "observation.json").write_text(json.dumps(record, indent=2) + "\n")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--case", action="append", default=None)
    arguments = parser.parse_args()
    spec = json.loads((HERE / "cases.json").read_text())
    out = arguments.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    cases = [c for c in spec["cases"]
             if not arguments.case or c["id"] in arguments.case]
    records = []
    for case in cases:
        record = run_case(case, out, arguments.live)
        records.append(record)
        print(json.dumps({k: record.get(k) for k in
                          ("case", "skills_bare", "consultation_skills_succeeded",
                           "satisfied", "vacuous", "violations", "returncode",
                           "disposition")}), flush=True)
    (out / "summary.json").write_text(json.dumps(
        {"protocol": spec["protocol"], "acs_plugin_version": json.loads(
            (ACS / ".claude-plugin" / "plugin.json").read_text())["version"],
         "cli": subprocess.run([CLI, "--version"], capture_output=True, text=True).stdout.strip(),
         "cases": records}, indent=2) + "\n")
    return exit_code(records)


if __name__ == "__main__":
    sys.exit(main())
