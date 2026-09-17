#!/usr/bin/env python3
"""List the prompts the INSTALLED activation hook actually routed to one skill.

Claude Code records hook output in session transcripts as `hook_additional_context`
attachments. This keeps the UserPromptSubmit ones whose routing block selects the skill (a
`<name> -> Skill(<plugin>:<name>)` line), and follows the attachment's parentUuid chain to
the prompt it answered. Each prompt is labelled by source exactly as extract.py labels it;
a routing whose chain reaches no prompt is labelled "unpaired". Live routings reflect
whichever plugin version was installed at the time, not the current triggers; replay.sh
measures those.

Writes a JSONL of the routed prompts (source, ts, project, prompt), one line per prompt,
which replay.sh accepts as input. The output holds prompt text, so a path inside a git work
tree is refused (exit 2). --since applies to the prompt's date.

Usage:
  routed.py --skill NAME --out FILE [--plugin NAME] [--projects DIR] [--since YYYY-MM-DD]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import glob  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract import iter_entries, prompt_of, refuse_repo_path, source_of, valid_since  # noqa: E402


def input_kind(entry):
    """The source of an input entry that is not a prompt (a notification, a tool result, a
    wrapper), or "" when the entry is not an input at all. Walking stops at any input, so a
    routing that followed a notification is never pinned on an earlier prompt."""
    att = entry.get("attachment")
    if entry.get("type") == "attachment" and isinstance(att, dict) and att.get("type") == "queued_command":
        return source_of(att.get("origin"), entry) if att.get("origin") else str(att.get("commandMode") or "queued")
    if entry.get("type") == "user":
        return source_of(entry.get("origin"), entry)
    return ""


def routes_to(att, pattern):
    if att.get("type") != "hook_additional_context" or att.get("hookEvent") != "UserPromptSubmit":
        return False
    content = att.get("content")
    if isinstance(content, list):
        content = "\n".join(c for c in content if isinstance(c, str))
    return isinstance(content, str) and "SKILL ACTIVATION" in content and bool(pattern.search(content))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skill", required=True)
    ap.add_argument("--plugin", default="auto-claude-skills")
    ap.add_argument("--out", required=True)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", default="", type=valid_since)
    args = ap.parse_args()
    if refuse_repo_path(args.out):
        return 2

    name = re.escape(args.skill)
    pattern = re.compile(r"(?m)(?:^|[\s:])" + name + r" -> Skill\(" + re.escape(args.plugin)
                         + ":" + name + r"\)")
    counts = {}
    total = 0
    with open(args.out, "w", encoding="utf-8") as fh:
        for path in sorted(glob.glob(os.path.join(args.projects, "*", "*.jsonl"))):
            project = os.path.basename(os.path.dirname(path))
            entries = list(iter_entries(path))
            by_uuid = {e["uuid"]: e for e in entries if isinstance(e.get("uuid"), str)}
            seen = set()
            for entry in entries:
                att = entry.get("attachment")
                if entry.get("type") != "attachment" or not isinstance(att, dict) or not routes_to(att, pattern):
                    continue
                prompt_entry, got, hops = None, None, 0
                node = by_uuid.get(entry.get("parentUuid"))
                while node is not None and hops < 50:
                    got = prompt_of(node)
                    if got or input_kind(node):
                        prompt_entry = node
                        break
                    node = by_uuid.get(node.get("parentUuid"))
                    hops += 1
                key = prompt_entry.get("uuid") if prompt_entry else entry.get("uuid")
                if key in seen:
                    continue
                seen.add(key)
                ts = str((prompt_entry or entry).get("timestamp", ""))[:10]
                if args.since and ts < args.since:
                    continue
                if got:
                    source = got[1]
                elif prompt_entry is not None:
                    source = "not-a-prompt:" + input_kind(prompt_entry)
                else:
                    source = "unpaired"
                total += 1
                counts[source] = counts.get(source, 0) + 1
                fh.write(json.dumps({"source": source, "ts": ts, "project": project,
                                     "prompt": got[0] if got else ""}) + "\n")
    print(f"routings {total}")
    for source in sorted(counts):
        print(f"source {source}: {counts[source]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
