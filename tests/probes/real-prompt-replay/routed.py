#!/usr/bin/env python3
"""List the prompts the INSTALLED activation hook actually routed to one skill.

Claude Code records hook output in session transcripts as `hook_additional_context`
attachments. This finds the routing outputs ("SKILL ACTIVATION ...") that name
`Skill(<plugin>:<skill>)` and pairs each with the user entry it followed. A prompt is
"human" when extract.py would keep it; notifications, resumed-session summaries and
similar are "non-human". Live routings reflect whichever plugin version was installed
at the time, not the current triggers; replay.sh measures those.

The output holds prompt text, so an output path inside the repository is refused (exit 2).

Usage:
  routed.py --skill NAME --out FILE [--projects DIR] [--since YYYY-MM-DD]
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract import REPO_ROOT, prompt_text  # noqa: E402


def raw_user_text(entry):
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        content = " ".join(b.get("text", "") for b in content
                           if isinstance(b, dict) and b.get("type") == "text")
    return content if isinstance(content, str) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", default="")
    args = ap.parse_args()

    out = os.path.realpath(args.out)
    if out == REPO_ROOT or out.startswith(REPO_ROOT + os.sep):
        print(f"refusing to write prompt text inside the repository: {out}", file=sys.stderr)
        return 2

    needle = f":{args.skill})"
    total = human = 0
    with open(out, "w", encoding="utf-8") as fh:
        for path in sorted(glob.glob(os.path.join(args.projects, "*", "*.jsonl"))):
            project = os.path.basename(os.path.dirname(path))
            last_entry = None
            with open(path, encoding="utf-8", errors="replace") as src:
                for line in src:
                    try:
                        entry = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(entry, dict):
                        continue
                    if entry.get("type") == "user" and raw_user_text(entry) is not None:
                        last_entry = entry
                        continue
                    att = entry.get("attachment")
                    if entry.get("type") != "attachment" or not isinstance(att, dict):
                        continue
                    if att.get("type") != "hook_additional_context":
                        continue
                    blob = json.dumps(att)
                    if "SKILL ACTIVATION" not in blob or needle not in blob:
                        continue
                    ts = str(entry.get("timestamp", ""))
                    if args.since and ts[:10] < args.since:
                        continue
                    total += 1
                    kept = prompt_text(last_entry) if last_entry else None
                    kind = "human" if kept is not None else "non-human"
                    human += kind == "human"
                    text = kept if kept is not None else (raw_user_text(last_entry) or "" if last_entry else "")
                    flat = " ".join(text.split())[:500]
                    fh.write(f"{kind}\t{ts[:16]}\t{project}\t{flat}\n")
    print(f"routings {total}")
    print(f"human {human}")
    print(f"non-human {total - human}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
