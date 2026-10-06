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
changes what the assistant did next), only blocks that were actually DISPLAYED (a block
hidden for another reason, such as non-human input, was seen by nobody), and only records
written for a prompt the transcript labels as typed by the user. Rows
are written in row_id order, which is a hash, so hidden and unhidden rows are interleaved.

INSTRUMENT CHECK. "Typed" means the transcript's own origin label is exactly "human" and the
text does not start with "<" (a wrapper block; a person who really types markup first is
lost with it). If the transcript format ever labels typed prompts otherwise, every record
fails that test, and "no rows" would read as "too little data" when it is a broken reader.
So when displayed records exist and NOT ONE joins a typed prompt, this exits 2 and prints
what the transcript called the prompts they were written for. Nothing is written then.
A timing fault (records and prompts further apart than the join window) lands here too.
It is all-or-nothing on purpose: prompts of other origins are legitimately excluded, so a
PARTIAL loss is not refused. The origin counts are printed on every run; read them.

Both files hold prompt text. A path inside a git repository, or one git cannot vouch for,
is refused (exit 2). Prints counts only.

COLLECTION STATUS. The pre-registration closes stage A when 60 rows the rule would hide
have been recorded, or on 2026-11-16, whichever is first, and stage A is scored ONCE. With
--count-only nothing is written: the same rows are built, the counts are printed, and the
last line says whether collection is OPEN or CLOSED. That is the check to run before
labelling; it reads no label and prints no prompt.

Usage:
  rows.py --shadow-log FILE --since ISO8601 --rows FILE --key FILE [--projects DIR]
  rows.py --shadow-log FILE --since ISO8601 --count-only [--projects DIR]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import collections  # noqa: E402
import datetime  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import RULE_VERSION, join, open_private, read_session, read_shadow, rec_ts, refuse_repo_path, transcript_for, ts_of  # noqa: E402

CLOSE_AT_HIDDEN_ROWS = 60     # pre-registered: collection closes at this many would-hide rows
CLOSE_ON = "2026-11-16"       # or on this date, whichever is first
TAIL = 1500        # characters of the previous assistant message
EARLIER = 8        # earlier typed prompts shown, most recent last
EACH = 500         # characters of each earlier prompt


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shadow-log", required=True)
    ap.add_argument("--since", required=True, help="ISO-8601 freeze timestamp; sessions that started earlier are excluded")
    ap.add_argument("--rows")
    ap.add_argument("--key")
    ap.add_argument("--count-only", action="store_true", help="write nothing; print the counts and whether collection is open")
    ap.add_argument("--today", help=argparse.SUPPRESS)   # tests only: the date to judge the closing date against
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    args = ap.parse_args()
    if not args.count_only and not (args.rows and args.key):
        print("--rows and --key are required unless --count-only is given", file=sys.stderr)
        return 2
    if args.count_only and (args.rows or args.key):
        print("--count-only writes nothing: do not pass --rows or --key with it", file=sys.stderr)
        return 2
    today = args.today or datetime.date.today().isoformat()
    if ts_of(today + "T00:00:00+00:00") is None:
        print(f"not a date: {today}", file=sys.stderr)
        return 2

    since = ts_of(args.since)
    if since is None:
        print(f"not an ISO-8601 timestamp: {args.since}", file=sys.stderr)
        return 2
    for out in (() if args.count_only else (args.rows, args.key)):
        if refuse_repo_path(out):
            return 2

    records, bad = read_shadow(args.shadow_log)
    counts = {"records": len(records), "malformed lines": bad, "not shadow mode": 0, "another rule version": 0, "block not displayed": 0, "before the freeze": 0, "no transcript": 0,
              "session started before the freeze": 0, "no typed prompt within the join window": 0,
              "second record for one prompt": 0, "rows": 0}
    sessions, rows, keys, used = {}, [], [], set()
    candidates, origins = 0, collections.Counter()
    for rec in records:
        if rec.get("mode") != "shadow":
            counts["not shadow mode"] += 1
            continue
        if rec.get("rule_version") != RULE_VERSION:
            counts["another rule version"] += 1
            continue
        if rec.get("other_suppression") or not rec.get("displayed"):
            counts["block not displayed"] += 1
            continue
        if rec_ts(rec) < since:
            counts["before the freeze"] += 1
            continue
        if not isinstance(rec.get("skills_in_block"), int) or isinstance(rec.get("skills_in_block"), bool):
            counts["malformed lines"] += 1      # a version-2 record always carries the count
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
        candidates += 1
        idx = join(rec, turns)
        if idx is None:
            counts["no typed prompt within the join window"] += 1
            near = join(rec, turns, any_source=True)
            if near is None:
                origins["no prompt of any origin in the window"] += 1
            else:
                label = str(turns[near]["source"])
                origins[f'origin "{label}"' + (", text starts with <" if turns[near]["text"].lstrip().startswith("<") else "")] += 1
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
            "skills_in_block": int(rec.get("skills_in_block") or 0),
            "block_chars": int(rec.get("block_chars") or 0),
            "invoked_same_turn": rec["skill"] in turn["skills"],
            "invoked_later": rec["skill"] in later,
        })
    counts["rows"] = len(rows)
    if candidates and not rows:
        print(f"INSTRUMENT FAULT: {candidates} displayed records, and not one joined a typed prompt.", file=sys.stderr)
        for name, n in origins.most_common():
            print(f"  {n:6d}  {name}", file=sys.stderr)
        print("Nothing was written. This is not a verdict and not 'too few rows'. Check how the transcript labels a typed", file=sys.stderr)
        print("prompt (the origins above) AND the timing: a record joins a prompt at most 15 s before it.", file=sys.stderr)
        return 2
    order = sorted(range(len(rows)), key=lambda i: rows[i]["row_id"])
    if not args.count_only:
        with open_private(args.rows) as out:
            for i in order:
                out.write(json.dumps(rows[i], ensure_ascii=False) + "\n")
        with open_private(args.key) as out:
            for i in order:
                out.write(json.dumps(keys[i]) + "\n")
    for name, n in counts.items():
        print(f"{n:6d}  {name}")
    for name, n in origins.most_common():
        print(f"{n:6d}    of those unjoined: {name}")
    print(f"{sum(1 for k in keys if k['would_hide']):6d}  rows the rule would hide")
    print(f"{len({k['session'] for k in keys}):6d}  sessions")
    hidden = sum(1 for k in keys if k["would_hide"])
    if hidden >= CLOSE_AT_HIDDEN_ROWS:
        print(f"collection: CLOSED ({hidden} rows the rule would hide; closes at {CLOSE_AT_HIDDEN_ROWS}). Label and score once.")
    elif today >= CLOSE_ON:
        print(f"collection: CLOSED (closing date {CLOSE_ON} reached with {hidden} rows the rule would hide). Label and score once.")
    else:
        print(f"collection: OPEN ({hidden} of {CLOSE_AT_HIDDEN_ROWS} rows the rule would hide; closes at {CLOSE_AT_HIDDEN_ROWS} or on {CLOSE_ON}). Do not label or score yet.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as err:  # noqa: BLE001 -- deliberately everything
        # A failure inside main() must not look like a verdict: an unhandled exception exits
        # 1, and 1 is a decision (STOP / HARM). SystemExit is not an Exception, so the verdict
        # codes returned above pass through untouched. Not covered: a failure while importing,
        # above this guard, and KeyboardInterrupt. This also swallows the traceback of a bug in
        # this script; the type and message are printed.
        print(f"cannot read the inputs: {type(err).__name__}: {err}", file=sys.stderr)
        sys.exit(2)
