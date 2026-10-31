#!/usr/bin/env python3
"""One blind labeller for the #412 corpus (pre-registration
docs/plans/2026-10-31-frontend-hint-exposure-prereg.md, D2 and "Rubric (frozen)").

Sends the frozen rubric (the text between <!-- RUBRIC-BEGIN --> and <!-- RUBRIC-END --> in
--prereg, verbatim) and batches of rows (`<id><TAB><prompt>`, tabs and newlines replaced by
spaces) to a fresh headless `claude -p` per batch. Each run gets its own temporary HOME (a
Library symlink and a copy of ~/.claude.json without MCP servers), an empty working
directory, no CLAUDE* environment variables, no MCP servers, no tools (`--tools ""`, with a
denylist as a backstop) and no persisted session, so it sees only the rubric and the rows:
never the stratum, routes, matches or weights. Rows are shuffled with --seed so batches mix
strata.

An answer line is `<id> <UI|NOT>` (tab or spaces). A row sent but not answered exactly once
with UI or NOT is re-asked once, alone; still unanswered, it is MALFORMED, which score.py
treats as a disagreement for the owner. An id that was not sent is ignored. A RUN that fails
(non-zero exit, timeout, unparseable output, or `is_error`) answers nothing, whatever its text
says; a row whose last attempt was such a run is FAILED, and the harness exits 4 so the
labelling is redone rather than adjudicated: a dead labeller must not quietly turn 2-of-3
into owner-plus-one.

Writes <draw-dir>/<labeller>.tsv (`<id><TAB>UI|NOT|MALFORMED|FAILED`, id order) and
<labeller>-manifest.json (model, CLI version, rubric sha256, seed, batch size, counts including
failed runs, times), mode 0600. The draw dir holds prompt text, so one inside a git repository
is refused (exit 2).

Usage:
  label.py --draw-dir DIR --prereg FILE --model MODEL --labeller L1|L2 [--batch 25] [--seed 412]
           [--jobs 4] [--claude BIN]
Exit 0 labelled, 2 bad input, 4 a labeller run failed for some row (redo it).
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import concurrent.futures as cf  # noqa: E402
import datetime  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import random  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "real-prompt-replay"))
from extract import open_private, refuse_repo_path  # noqa: E402

RUBRIC_RE = re.compile(r"<!-- RUBRIC-BEGIN -->\n(.*?)\n<!-- RUBRIC-END -->", re.S)
ANSWER_RE = re.compile(r"^\s*(r\d{5})\s+(UI|NOT)\s*$")
NO_TOOLS = "Bash,Read,Edit,Write,MultiEdit,NotebookEdit,WebFetch,WebSearch,Agent,Task,Glob,Grep,TodoWrite"


def rubric_of(path):
    m = RUBRIC_RE.search(open(path, encoding="utf-8").read())
    if not m:
        raise ValueError("no RUBRIC-BEGIN/RUBRIC-END block in %s" % path)
    return m.group(1)


def flat(text):
    return re.sub(r"[\t\r\n]+", " ", text)


def isolated_home():
    home = tempfile.mkdtemp(prefix="acs-labeller-home-")
    os.makedirs(os.path.join(home, ".claude"))
    real = os.path.expanduser("~")
    lib = os.path.join(real, "Library")
    if os.path.isdir(lib):
        os.symlink(lib, os.path.join(home, "Library"))
    src = os.path.join(real, ".claude.json")
    if os.path.isfile(src):
        try:
            cj = json.load(open(src, encoding="utf-8"))
        except ValueError:
            cj = {}
        cj.pop("mcpServers", None)
        for proj in (cj.get("projects") or {}).values():
            if isinstance(proj, dict):
                proj.pop("mcpServers", None)
        json.dump(cj, open(os.path.join(home, ".claude.json"), "w", encoding="utf-8"))
    return home


def ask(claude, model, rubric, batch):
    """({id: label} for the rows answered exactly once with UI or NOT, whether the run failed)."""
    home, work = isolated_home(), tempfile.mkdtemp(prefix="acs-labeller-cwd-")
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
    env["HOME"] = home
    text = rubric + "\n\n" + "\n".join("%s\t%s" % (r["id"], flat(r["prompt"])) for r in batch) + "\n"
    cmd = [claude, "-p", "--model", model, "--output-format", "json", "--setting-sources", "project",
           "--strict-mcp-config", "--no-session-persistence", "--tools", "", "--disallowedTools", NO_TOOLS]
    result, failed = "", True
    try:
        run = subprocess.run(cmd, input=text, capture_output=True, text=True, cwd=work, env=env, timeout=900)
        out = json.loads(run.stdout) if run.returncode == 0 else None
        if isinstance(out, dict) and not out.get("is_error") and isinstance(out.get("result"), str):
            result, failed = out["result"], False
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    finally:
        shutil.rmtree(home, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    sent = {r["id"] for r in batch}
    seen = {}
    for line in str(result).splitlines():
        m = ANSWER_RE.match(line)
        if m and m.group(1) in sent:
            seen.setdefault(m.group(1), []).append(m.group(2))
    return {i: v[0] for i, v in seen.items() if len(v) == 1}, failed


def label_batch(claude, model, rubric, batch):
    """({id: UI|NOT|MALFORMED|FAILED} for every row of the batch, rows retried, failed runs)."""
    got, failed = ask(claude, model, rubric, batch)
    failed_runs = int(failed)
    out = dict(got)
    missing = [r for r in batch if r["id"] not in got]
    for r in missing:
        # Alone, so one row that breaks a run cannot take its batch mates with it.
        again, failed = ask(claude, model, rubric, [r])
        failed_runs += int(failed)
        out[r["id"]] = again.get(r["id"], "FAILED" if failed else "MALFORMED")
    return out, len(missing), failed_runs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--draw-dir", required=True)
    ap.add_argument("--prereg", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--labeller", required=True, choices=("L1", "L2"))
    ap.add_argument("--batch", type=int, default=25)
    ap.add_argument("--seed", type=int, default=412)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--claude", default="claude")
    a = ap.parse_args()
    if refuse_repo_path(os.path.abspath(a.draw_dir)):
        return 2
    try:
        rubric = rubric_of(a.prereg)
        with open(os.path.join(a.draw_dir, "rows.jsonl"), encoding="utf-8") as f:
            rows = [json.loads(line) for line in f if line.strip()]
    except (OSError, ValueError) as e:
        print("bad input: %s" % e, file=sys.stderr)
        return 2
    order = list(rows)
    random.Random(a.seed).shuffle(order)
    batches = [order[k:k + max(1, a.batch)] for k in range(0, len(order), max(1, a.batch))]
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    labels, retried, failed_runs = {}, 0, 0
    with cf.ThreadPoolExecutor(max(1, a.jobs)) as ex:
        for got, n, f in ex.map(lambda b: label_batch(a.claude, a.model, rubric, b), batches):
            labels.update(got)
            retried += n
            failed_runs += f
    try:
        version = subprocess.run([a.claude, "--version"], capture_output=True, text=True, timeout=60).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        version = None
    malformed = failed_rows = 0
    with open_private(os.path.join(a.draw_dir, a.labeller + ".tsv")) as f:
        for r in sorted(rows, key=lambda r: r["id"]):
            lab = labels.get(r["id"], "FAILED")
            malformed += lab == "MALFORMED"
            failed_rows += lab == "FAILED"
            f.write("%s\t%s\n" % (r["id"], lab))
    manifest = {"labeller": a.labeller, "model": a.model, "cli_version": version,
                "rubric_sha256": hashlib.sha256(rubric.encode("utf-8")).hexdigest(), "seed": a.seed,
                "batch": a.batch, "batches": len(batches), "rows": len(rows), "retried": retried,
                "malformed": malformed, "failed_runs": failed_runs, "failed_rows": failed_rows, "started": started,
                "finished": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    with open_private(os.path.join(a.draw_dir, a.labeller + "-manifest.json")) as f:
        json.dump(manifest, f, indent=1)
        f.write("\n")
    print("rows %d batches %d retried %d malformed %d failed runs %d failed rows %d" % (
        len(rows), len(batches), retried, malformed, failed_runs, failed_rows))
    if failed_rows:
        print("labeller runs failed for %d rows: rerun this labeller before adjudicating" % failed_rows, file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
