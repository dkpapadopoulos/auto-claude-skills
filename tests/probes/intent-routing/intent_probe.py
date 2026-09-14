#!/usr/bin/env python3
"""Deterministic intent-separation probe over the real ACS activation hook.

Records, per frozen case, the full hook output and the selected skills, then
compares the selection against the case's PRE-REGISTERED contract criterion.
No model is called. A criterion mismatch is a routing observation, not proof
that the subsequent model behavior would be wrong.
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
ROOT = _repo_root(HERE)
CASES = HERE / "cases.json"

# Selected skills are emitted as `Skill(<plugin>:<name>)` in the activation block.
SKILL_CALL = re.compile(r"Skill\(([a-z0-9-]+):([a-z0-9-]+)\)")
# The phase composition chain block; its presence on a phase-agnostic request is
# the separate "simplify phase injection" observation.
CHAIN_LINE = re.compile(r"^Composition: (.+)$", re.MULTILINE)
STEP_LINE = re.compile(r"^\s*\[(CURRENT|NEXT|LATER)\] Step \d+: Skill\(([^)]+)\)", re.MULTILINE)


def run_hook(home, payload):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("SKILL_", "CLAUDE_")):
            env.pop(key)
    env.update(HOME=str(home), CLAUDE_PLUGIN_ROOT=str(ROOT),
               SKILL_PROJECT_ROOT=str(ROOT), SKILL_EXPLAIN="1")
    started = time.monotonic()
    result = subprocess.run(["/bin/bash", str(ROOT / "hooks" / "skill-activation-hook.sh")],
                            input=json.dumps(payload), text=True, capture_output=True,
                            env=env, cwd=ROOT, timeout=30)
    return {"returncode": result.returncode, "stdout": result.stdout,
            "stderr": result.stderr, "elapsed_seconds": round(time.monotonic() - started, 4)}


def prepare_home(home, controlled):
    target = home / ".claude"
    target.mkdir()
    if controlled:
        registry = json.loads((ROOT / "config/default-triggers.json").read_text())
        for skill in registry["skills"]:
            skill.update(available=True, enabled=True)
        (target / ".skill-registry-cache.json").write_text(json.dumps(registry))
    return {"transcript_path": str(target / "audit.jsonl")}


def analyze(stdout, criterion):
    """Selection is read from the ACTIVATION block only. Step lines of an injected
    composition chain name future phase skills and are reported separately; counting
    them as selections would report the chain as an intent match."""
    # Empty stdout is the hook's NO-ACTIVATION result, not a parse failure. Collapsing
    # the two reports a correct "nothing selected" as a broken instrument, and would
    # silently turn every satisfied `expect_absent` case into an unmeasured one.
    if stdout.strip() == "":
        no_activation = True
        context = ""
    else:
        no_activation = False
        try:
            context = json.loads(stdout)["hookSpecificOutput"]["additionalContext"]
        except Exception:
            return {"parsed": False, "no_activation": False, "selected": [], "chain": None,
                    "chain_steps": [], "satisfied": None,
                    "violations": ["hook output present but not parseable"]}
    chain_match = CHAIN_LINE.search(context)
    # Bare skill names, so chain steps are directly comparable with `selected`;
    # a plugin-qualified list silently never matches and reads as "no overlap".
    chain_steps = [m.group(2).split(":")[-1] for m in STEP_LINE.finditer(context)]
    step_region = context[chain_match.start():] if chain_match else ""
    selected = sorted({name for plugin, name in SKILL_CALL.findall(context[:chain_match.start()]
                                                                   if chain_match else context)})
    violations = []
    for name in criterion.get("expect_present", []):
        if name not in selected:
            violations.append(f"expected present: {name}")
    for name in criterion.get("expect_absent", []):
        if name in selected:
            violations.append(f"expected absent: {name}")
    # A criterion made only of `expect_absent` clauses is trivially satisfied when the
    # hook selects nothing at all. Counting those as evidence of intent separation is
    # the same error as an assertion the fallback path also passes: it pins nothing.
    # They are reported as satisfied AND vacuous, and excluded from the informative
    # denominator.
    vacuous = (not violations and no_activation and not criterion.get("expect_present"))
    return {"parsed": True, "no_activation": no_activation, "selected": selected,
            "chain": chain_match.group(1) if chain_match else None,
            "chain_steps": chain_steps,
            "phase_chain_injected": chain_match is not None,
            "satisfied": not violations, "vacuous": vacuous, "violations": violations,
            "step_region_bytes": len(step_region)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    spec = json.loads(CASES.read_text())
    rows = []
    for controlled in (False, True):
        arm = "controlled-all-skills" if controlled else "shipped-fallback"
        for case in spec["cases"]:
            with tempfile.TemporaryDirectory(prefix="acs-intent-") as scratch:
                home = Path(scratch)
                payload = prepare_home(home, controlled)
                payload["prompt"] = case["prompt"]
                row = run_hook(home, payload)
            row.update(arm=arm, case_id=case["id"], contract=case["contract"],
                       prompt=case["prompt"])
            row["analysis"] = analyze(row["stdout"], spec["criteria"][case["contract"]])
            rows.append(row)
    (out / "runs.json").write_text(json.dumps(rows, indent=2) + "\n")
    (out / "cases-used.json").write_text(json.dumps(spec, indent=2) + "\n")

    matrix = []
    for row in rows:
        a = row["analysis"]
        matrix.append({"arm": row["arm"], "case": row["case_id"], "contract": row["contract"],
                       "selected": a["selected"], "no_activation": a.get("no_activation"),
                       "satisfied": a["satisfied"], "vacuous": a.get("vacuous"),
                       "violations": a["violations"],
                       "phase_chain_injected": a.get("phase_chain_injected")})
    tallies = {}
    for arm in sorted({r["arm"] for r in matrix}):
        rows_a = [r for r in matrix if r["arm"] == arm]
        inf_a = [r for r in rows_a if r["satisfied"] is not None and not r["vacuous"]]
        tallies[arm] = {"runs": len(rows_a), "informative": len(inf_a),
                        "vacuously_satisfied": sum(1 for r in rows_a if r["vacuous"]),
                        "satisfied_informative": sum(1 for r in inf_a if r["satisfied"]),
                        "violated": sum(1 for r in rows_a if r["satisfied"] is False),
                        # A violation produced by selecting NOTHING is the shipped
                        # missing-capability fallback, not evidence about intent
                        # separation. Reported apart so the two are never summed.
                        "violated_via_no_activation": sum(
                            1 for r in rows_a if r["satisfied"] is False and r["no_activation"]),
                        "no_activation": sum(1 for r in rows_a if r["no_activation"]),
                        "phase_chain_injected": sum(1 for r in rows_a
                                                    if r.get("phase_chain_injected"))}
    summary = {"protocol": spec["protocol"], "cases": len(spec["cases"]), "runs": len(rows),
               "all_hook_exit_zero": all(r["returncode"] == 0 for r in rows),
               "tallies": tallies, "matrix": matrix,
               "scope": "Deterministic routing observation only. It does not establish what a "
                        "model would have done after the injection, nor that a violated "
                        "criterion produced a worse outcome."}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
