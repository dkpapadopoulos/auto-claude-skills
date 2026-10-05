#!/usr/bin/env python3
"""Build the labelling set for the sticky-repeat screen (#333, stage A).

Reads the activation hook's shadow records (its record directory, one file per record) and
the session transcripts, and writes TWO files:

  --rows  what a labeller sees: the prompt, the context before it, and the ONE process skill
          the routing block required. Nothing about the rule: not whether the mandate was
          sticky, not whether it was shown before, not whether the rule would hide it.
  --key   row_id -> the hook's own record and what happened next. Never shown to a labeller.

Only sessions that STARTED at or after --since count (the freeze timestamp), only records
the hook wrote in SHADOW mode (in any other mode some blocks were really hidden, which
changes what the assistant did next), and only records written for a typed prompt. Rows
are written in row_id order, which is a hash, so hidden and unhidden rows are interleaved.

Both files hold prompt text. A path inside a git repository, or one git cannot vouch for,
is refused (exit 2). Prints counts only.

Usage:
  rows.py --shadow-log FILE --since ISO8601 --rows FILE --key FILE [--projects DIR]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import join, open_private, read_session, read_shadow, rec_ts, refuse_repo_path, transcript_for, ts_of  # noqa: E402

RULE_VERSION = 1   # the pre-registered rule; a record written by a changed rule is not a row
TAIL = 1500        # characters of the previous assistant message
EARLIER = 8        # earlier typed prompts shown, most recent last
EACH = 500         # characters of each earlier prompt


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shadow-log", required=True)
    ap.add_argument("--since", required=True, help="ISO-8601 freeze timestamp; sessions that started earlier are excluded")
    ap.add_argument("--rows", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    args = ap.parse_args()

    since = ts_of(args.since)
    if since is None:
        print(f"not an ISO-8601 timestamp: {args.since}", file=sys.stderr)
        return 2
    for out in (args.rows, args.key):
        if refuse_repo_path(out):
            return 2

    records, bad = read_shadow(args.shadow_log)
    counts = {"records": len(records), "malformed lines": bad, "not shadow mode": 0, "another rule version": 0, "before the freeze": 0, "no transcript": 0,
              "session started before the freeze": 0, "no typed prompt within the join window": 0,
              "second record for one prompt": 0, "rows": 0}
    sessions, rows, keys, used = {}, [], [], set()
    for rec in records:
        if rec.get("mode") != "shadow":
            counts["not shadow mode"] += 1
            continue
        if rec.get("rule_version") != RULE_VERSION:
            counts["another rule version"] += 1
            continue
        if rec_ts(rec) < since:
            counts["before the freeze"] += 1
            continue
        sid = rec["session"]
        if sid not in sessions:
            path = transcript_for(args.projects, sid)
            sessions[sid] = read_session(path) if path else None
        if sessions[sid] is None:
            counts["no transcript"] += 1
            continue
        started, turns = sessions[sid]
        if started is None or started < since:
            counts["session started before the freeze"] += 1
            continue
        idx = join(rec, turns)
        if idx is None:
            counts["no typed prompt within the join window"] += 1
            continue
        if (sid, idx) in used:
            counts["second record for one prompt"] += 1
            continue
        used.add((sid, idx))
        turn = turns[idx]
        row_id = hashlib.sha256(f"{sid}\x1f{idx}\x1f{rec['ts']}".encode()).hexdigest()[:12]
        earlier = [t for t in turns[:idx]]
        rows.append({
            "row_id": row_id,
            "skill": rec["skill"],
            "prompt": turn["text"],
            "previous_assistant_message_tail": (turn["prev_assistant"] or "")[-TAIL:],
            "earlier_prompts": [t["text"][:EACH] for t in earlier[-EARLIER:]],
            "tools_used_since_the_previous_prompt": (turns[idx - 1]["tools"] if idx > 0 else []),
            "process_skills_already_invoked_this_session": sorted({s for t in earlier for s in t["skills"]}),
        })
        later = [s for t in turns[idx + 1:] for s in t["skills"]]
        keys.append({
            "row_id": row_id, "session": sid, "ts": rec["ts"], "skill": rec["skill"],
            "sticky": bool(rec.get("sticky")), "already_shown": bool(rec.get("already_shown")),
            "would_hide": bool(rec.get("would_hide")), "mode": rec.get("mode"), "arm": rec.get("arm"),
            "hidden_by_rule": bool(rec.get("hidden_by_rule")), "displayed": bool(rec.get("displayed")),
            "other_suppression": bool(rec.get("other_suppression")),
            "block_chars": int(rec.get("block_chars") or 0),
            "invoked_same_turn": rec["skill"] in turn["skills"],
            "invoked_later": rec["skill"] in later,
        })
    counts["rows"] = len(rows)
    order = sorted(range(len(rows)), key=lambda i: rows[i]["row_id"])
    with open_private(args.rows) as out:
        for i in order:
            out.write(json.dumps(rows[i], ensure_ascii=False) + "\n")
    with open_private(args.key) as out:
        for i in order:
            out.write(json.dumps(keys[i]) + "\n")
    for name, n in counts.items():
        print(f"{n:6d}  {name}")
    print(f"{sum(1 for k in keys if k['would_hide']):6d}  rows the rule would hide")
    print(f"{len({k['session'] for k in keys}):6d}  sessions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
