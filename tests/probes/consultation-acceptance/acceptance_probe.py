#!/usr/bin/env python3
"""Observation runner for the held-out consultation acceptance prompts.

Deterministic and free: it drives the REAL activation hook against an isolated HOME
and calls no model.

This records what the hook DOES with each held-out prompt. It deliberately does not
yet judge pass/fail -- the contracts it will be judged against (a one-participant
consultation method, and consultation/development discrimination) are not implemented,
so a criterion written now would encode today's defects as the target.

Two things are recorded per case that a selection-only probe cannot see:

  * whether a development composition CHAIN was started, read from the state file the
    hook writes rather than from the rendered text; and
  * for the sequential categories, whether an ALREADY ACTIVE chain survived.

The second is the regression ACCEPTANCE.md names as the likeliest way this change set
breaks something nothing measured -- suppressing legitimate development routing during
a consultation detour.
"""
import argparse
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path


def _repo_root(start):
    """Walk up to the repository root by MARKER, not by counting directories."""
    for candidate in [start, *start.parents]:
        if ((candidate / ".claude-plugin" / "plugin.json").is_file()
                and (candidate / "config" / "default-triggers.json").is_file()):
            return candidate
    raise SystemExit(f"repository root not found above {start}")


HERE = Path(__file__).resolve().parent
ROOT = _repo_root(HERE)
CASES = HERE / "cases.json"

SKILL_CALL = re.compile(r"Skill\(([a-z0-9-]+):([a-z0-9-]+)\)")
CHAIN_LINE = re.compile(r"^Composition: (.+)$", re.MULTILINE)
ACTIVATION_HEAD = re.compile(r"^SKILL ACTIVATION", re.MULTILINE)

# Establishes a development workflow before a sequential case runs. Deliberately
# contains no consultation vocabulary, so any chain it starts is unambiguously
# development intent.
PREAMBLE = "add retry handling to the ingest worker"
SEQUENTIAL = ("continuation", "cancellation")


def run_hook(home, prompt, transcript):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("SKILL_", "CLAUDE_")):
            env.pop(key)
    env.update(HOME=str(home), CLAUDE_PLUGIN_ROOT=str(ROOT), SKILL_PROJECT_ROOT=str(ROOT))
    payload = {"prompt": prompt, "transcript_path": str(transcript)}
    result = subprocess.run(["/bin/bash", str(ROOT / "hooks" / "skill-activation-hook.sh")],
                            input=json.dumps(payload), text=True, capture_output=True,
                            env=env, cwd=ROOT, timeout=30)
    return result.stdout


def prepare_home(home):
    """Every skill available, so a miss is a routing decision and not an install gap."""
    target = home / ".claude"
    target.mkdir(parents=True, exist_ok=True)
    registry = json.loads((ROOT / "config/default-triggers.json").read_text())
    for skill in registry["skills"]:
        skill.update(available=True, enabled=True)
    (target / ".skill-registry-cache.json").write_text(json.dumps(registry))
    return target / "audit.jsonl"


def read_state(home):
    """Chain state as the hook actually persisted it.

    Read from the state file, not the rendered block: the rendered chain and the
    persisted chain are written by different code paths, and it is the persisted one
    that later turns and the push gate read.
    """
    states = sorted((home / ".claude").glob(".skill-composition-state-*"))
    if not states:
        return {"chain": None, "completed": None}
    try:
        state = json.loads(states[0].read_text())
    except (json.JSONDecodeError, OSError):
        return {"chain": "unreadable", "completed": "unreadable"}
    return {"chain": state.get("chain"), "completed": state.get("completed")}


def observe(stdout):
    """Selection is read from the ACTIVATION block ONLY.

    The rendered composition chain lists future-phase skills as Skill(...) step lines
    too. Matching every Skill(...) in the output counts those as selections, which
    reports an injected chain as an intent match -- it inflated a three-skill
    selection to twelve when this runner was first written. The frozen probe carries
    the same warning; the rule is load-bearing, not stylistic.
    """
    if stdout.strip() == "":
        # The hook's NO-ACTIVATION result, not a parse failure. Collapsing the two
        # would report a correct "nothing selected" as a broken instrument.
        return {"activated": False, "parsed": True, "selected": [], "chain_rendered": None}
    try:
        context = json.loads(stdout)["hookSpecificOutput"]["additionalContext"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return {"activated": None, "parsed": False, "selected": [], "chain_rendered": None}
    chain = CHAIN_LINE.search(context)
    region = context[:chain.start()] if chain else context
    return {
        "activated": bool(ACTIVATION_HEAD.search(context)),
        "parsed": True,
        "selected": sorted({name for _plugin, name in SKILL_CALL.findall(region)}),
        "chain_rendered": chain.group(1).strip() if chain else None,
    }


def run_case(case):
    with tempfile.TemporaryDirectory(prefix="acs-acceptance-") as temporary:
        home = Path(temporary)
        transcript = prepare_home(home)
        record = {"case": case["id"], "contract": case["contract"]}
        if case["contract"] in SEQUENTIAL:
            run_hook(home, PREAMBLE, transcript)
            before = read_state(home)
            record["preamble_chain_length"] = len(before["chain"] or [])
            record["preamble_completed"] = before["completed"]
        started = time.monotonic()
        stdout = run_hook(home, case["prompt"], transcript)
        record["elapsed_seconds"] = round(time.monotonic() - started, 3)
        record.update(observe(stdout))
        after = read_state(home)
        record["chain_persisted"] = after["chain"]
        record["chain_persisted_length"] = len(after["chain"] or [])
        record["completed_persisted"] = after["completed"]
        return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--case", action="append", default=None)
    arguments = parser.parse_args()
    spec = json.loads(CASES.read_text())
    cases = [c for c in spec["cases"] if not arguments.case or c["id"] in arguments.case]
    records = [run_case(case) for case in cases]
    out = arguments.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    summary = {"protocol": spec["protocol"], "authoring_rule": spec["authoring_rule"],
               "note": ("OBSERVATION ONLY. No pass/fail: the contracts these prompts will "
                        "be judged against are not implemented yet, and a criterion "
                        "written now would encode today's defects as the target."),
               "records": records}
    out.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
    for record in records:
        print(json.dumps({k: record.get(k) for k in
                          ("case", "contract", "selected", "chain_persisted_length")},
                         ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
