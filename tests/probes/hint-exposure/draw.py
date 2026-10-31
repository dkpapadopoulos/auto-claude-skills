#!/usr/bin/env python3
"""Draw the #412 labelling corpus (pre-registration docs/plans/2026-10-31-frontend-hint-exposure-prereg.md, D3, D8).

A row is a typed prompt (the census definition) in [--since, --until), read from every
top-level transcript under --projects with its Cozempic .bak copies merged, each entry uuid
once across the whole corpus. Stratum A: the prompt's OWN paired routing block (followed by
parentUuid, never a SessionStart or compaction-resume context) lists frontend-design on its
verdict line or renders one of the three frontend hints (a line starting "- <LABEL>").
Stratum B: every other row; n_B = min(--n-b, N_B) of them are drawn uniformly with --seed.
Weights: 1 in A, N_B/n_B in B.

For Q2 (descriptive), each row records which of frontend-design and runtime-validation its
block lists, and for each the turn's class: loaded-earlier (invoked before the prompt in the
session), in-turn, direct-validation (no invocation in the turn, but a browser, screenshot
or Playwright tool call in it), later, or unknown; in that order of precedence.

Writes to --out-dir, which must be outside every git repository (mode 0600 files):
  rows.jsonl     id, stratum, weight, prompt, named, routes, listed, q2; ordered by id
  prompts.jsonl  {"prompt": ...} in the same order: the replay.sh input, line i = row i
  manifest.json  transcripts and backups read (path, size, sha256), cutoff, seed, counts,
                 the blob shas of this script and the readers it imports, HINT_LABELS
Prints counts and the manifest's sha256 only: no prompt text, no paths.

Usage:
  draw.py --projects DIR --since ISO --until ISO --seed INT --out-dir DIR [--n-b 300]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import glob  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import random  # noqa: E402
import re  # noqa: E402
import subprocess  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "compliance-census"))
sys.path.insert(0, os.path.join(HERE, "..", "real-prompt-replay"))
import census  # noqa: E402
from extract import open_private, prompt_of, refuse_repo_path  # noqa: E402

ROUTES = ("frontend-design", "frontend-playwright", "frontend-quality-rules", "design-seed")
# Every leading label each hint carried in config/default-triggers.json since 2026-08-25
# (26 versions read with git log -p on 2026-10-31; none changed). A hint renders as "- <hint>".
HINT_LABELS = {
    "frontend-playwright": ("PLAYWRIGHT TESTING:",),
    "frontend-quality-rules": ("FRONTEND QUALITY:",),
    "design-seed": ("DESIGN SEED:",),
}
Q2_SKILLS = ("frontend-design", "runtime-validation")
NAMED_RE = re.compile(r"frontend[- ]design", re.IGNORECASE)
DIRECT_TOOL_RE = re.compile(r"browser|chrome|playwright", re.IGNORECASE)
DIRECT_BASH_RE = re.compile(r"playwright|screenshot|chromium|headless", re.IGNORECASE)


def routes_of(block):
    out = []
    listed = census.routed_names(block)
    lines = block.splitlines()
    for route in ROUTES:
        if route == "frontend-design":
            hit = route in listed
        else:
            hit = any(line.startswith("- " + label) for line in lines for label in HINT_LABELS[route])
        if hit:
            out.append(route)
    return out


def direct_validation(entry):
    if entry.get("type") != "assistant":
        return False
    msg = entry.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    for block in content if isinstance(content, list) else []:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        name = str(block.get("name") or "")
        if DIRECT_TOOL_RE.search(name):
            return True
        if name == "Bash" and DIRECT_BASH_RE.search(str((block.get("input") or {}).get("command") or "")):
            return True
    return False


def q2_class(skill, before, in_turn, after, direct):
    if skill in before:
        return "loaded-earlier"
    if skill in in_turn:
        return "in-turn"
    if direct:
        return "direct-validation"
    if skill in after:
        return "later"
    return "unknown"


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def blob_sha(path):
    try:
        return subprocess.check_output(["git", "hash-object", path], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def session_rows(path, projects, since, until, seen):
    """Rows of one session, as (sort key, row) pairs, and the copies read."""
    entries, _version, _merged, _bad = census.read_session_with_bak(path, projects)
    sid = os.path.basename(path)[:-len(".jsonl")]
    prompts = [prompt_of(e) for e in entries]
    stamps = [census.ts_of(e.get("timestamp")) for e in entries]
    by_uuid = {}
    for i, e in enumerate(entries):
        u = e.get("uuid")
        if isinstance(u, str) and u and u not in by_uuid:
            by_uuid[u] = i
    block_of = {}
    for i, e in enumerate(entries):
        text = census.block_text(e)
        if text is None:
            continue
        j = census.pair_block(i, by_uuid, entries, prompts)
        if j is not None and j != -1 and census.typed(prompts[j]):
            block_of.setdefault(j, text)
    positions = [i for i, p in enumerate(prompts) if p is not None or census.is_text_input(entries[i])]
    out = []
    for i, p in enumerate(prompts):
        s = stamps[i]
        if not census.typed(p) or s is None or s < since or s >= until:
            continue
        u = entries[i].get("uuid")
        key = u if isinstance(u, str) and u else "%s#%d" % (sid, i)
        if key in seen:
            continue
        seen.add(key)
        nxt = next((q for q in positions if q > i), len(entries))
        before = {n for e in entries[:i] for n in census.skill_uses(e)}
        in_turn = {n for e in entries[i + 1:nxt] for n in census.skill_uses(e)}
        after = {n for e in entries[nxt:] for n in census.skill_uses(e)}
        direct = any(direct_validation(e) for e in entries[i + 1:nxt])
        block = block_of.get(i)
        routes = routes_of(block) if block is not None else []
        names = census.routed_names(block) if block is not None else set()
        listed = [k for k in Q2_SKILLS if k in names]
        row = {"stratum": "A" if routes else "B", "prompt": p[0], "named": bool(NAMED_RE.search(p[0])),
               "routes": routes, "listed": listed,
               "q2": {k: q2_class(k, before, in_turn, after, direct) for k in listed}}
        out.append(((s, sid, key), row))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", required=True)
    ap.add_argument("--until", required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--n-b", type=int, default=300)
    ap.add_argument("--out-dir", required=True)
    a = ap.parse_args()
    since, until = census.ts_of(a.since), census.ts_of(a.until)
    if since is None or until is None or a.n_b < 1:
        print("--since and --until must be ISO-8601 times and --n-b positive", file=sys.stderr)
        return 2
    probe = os.path.abspath(a.out_dir)
    while not os.path.isdir(probe):
        probe = os.path.dirname(probe)
    if refuse_repo_path(probe):
        return 2

    paths = sorted(glob.glob(os.path.join(glob.escape(a.projects), "*", "*.jsonl")))
    seen, keyed, read, unreadable = set(), [], [], 0
    for path in paths:
        try:
            keyed.extend(session_rows(path, a.projects, since, until, seen))
        except OSError:
            unreadable += 1
            continue
        for copy in census.bak_copies(path, a.projects) + [path]:
            try:
                read.append({"path": copy, "size": os.path.getsize(copy), "sha256": sha256_of(copy)})
            except OSError:
                pass
    keyed.sort(key=lambda kr: kr[0])
    a_rows = [kr for kr in keyed if kr[1]["stratum"] == "A"]
    b_rows = [kr for kr in keyed if kr[1]["stratum"] == "B"]
    n_b = min(a.n_b, len(b_rows))
    drawn = sorted(random.Random(a.seed).sample(range(len(b_rows)), n_b)) if n_b else []
    weight_b = len(b_rows) / n_b if n_b else 0.0
    chosen = a_rows + [b_rows[k] for k in drawn]
    chosen.sort(key=lambda kr: kr[0])

    os.makedirs(a.out_dir, exist_ok=True)
    with open_private(os.path.join(a.out_dir, "rows.jsonl")) as rows_f, \
            open_private(os.path.join(a.out_dir, "prompts.jsonl")) as prompts_f:
        for n, (_key, row) in enumerate(chosen, 1):
            rec = {"id": "r%05d" % n, "stratum": row["stratum"],
                   "weight": 1 if row["stratum"] == "A" else weight_b}
            rec.update(row)
            rows_f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            prompts_f.write(json.dumps({"prompt": row["prompt"]}, ensure_ascii=False) + "\n")
    manifest = {
        "since": a.since, "until": a.until, "seed": a.seed, "n_b_requested": a.n_b,
        "N_A": len(a_rows), "N_B": len(b_rows), "n_B": n_b, "transcripts_unreadable": unreadable,
        "readers": {name: blob_sha(os.path.join(HERE, rel)) for name, rel in (
            ("draw.py", "draw.py"), ("census.py", "../compliance-census/census.py"),
            ("extract.py", "../real-prompt-replay/extract.py"))},
        "hint_labels": HINT_LABELS, "copies_read": read,
    }
    body = json.dumps(manifest, indent=1, sort_keys=True) + "\n"
    with open_private(os.path.join(a.out_dir, "manifest.json")) as f:
        f.write(body)
    print("stratum A: %d" % len(a_rows))
    print("stratum B: %d sampled %d" % (len(b_rows), n_b))
    print("copies read: %d, transcripts unreadable: %d" % (len(read), unreadable))
    print("manifest sha256: %s" % hashlib.sha256(body.encode("utf-8")).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
