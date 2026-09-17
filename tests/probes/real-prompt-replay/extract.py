#!/usr/bin/env python3
"""Extract every distinct human-typed prompt from local Claude Code transcripts.

The output holds your own prompt text, so it must never land in this repository: an
output path inside the repository is refused (exit 2). Write it to a temporary directory.

What counts as a human-typed prompt: a transcript entry of type "user" whose content is
text (a string, or text blocks), in a top-level session transcript. Excluded:
  - tool results (a user entry carrying a tool_result block);
  - subagent transcripts (only <projects>/<project>/<session>.jsonl is read);
  - meta and sidechain entries;
  - background-task notifications, resumed-session summaries, injected skill bodies,
    slash-command expansions and command-output wrappers (recognised by their prefix);
  - exact duplicates (the first occurrence is kept).

Usage:
  extract.py --out FILE [--projects DIR] [--since YYYY-MM-DD]
"""
import argparse
import glob
import json
import os
import sys

REPO_ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SKIP_PREFIX = (
    "<task-notification>", "This session is being continued", "Base directory for this skill",
    "<command-", "<local-command", "Caveat:", "[Request interrupted", "<system-reminder>",
    "<bash-", "<user-prompt-submit-hook>",
)


def prompt_text(entry):
    if entry.get("type") != "user" or entry.get("isMeta") or entry.get("isSidechain"):
        return None
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        content = " ".join(b.get("text", "") for b in content
                           if isinstance(b, dict) and b.get("type") == "text")
    if not isinstance(content, str):
        return None
    text = content.strip()
    if not text or text.startswith(SKIP_PREFIX):
        return None
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", default="")
    args = ap.parse_args()

    out = os.path.realpath(args.out)
    if out == REPO_ROOT or out.startswith(REPO_ROOT + os.sep):
        print(f"refusing to write prompt text inside the repository: {out}", file=sys.stderr)
        return 2

    files = sorted(glob.glob(os.path.join(args.projects, "*", "*.jsonl")))
    seen = set()
    with open(out, "w", encoding="utf-8") as fh:
        for path in files:
            project = os.path.basename(os.path.dirname(path))
            with open(path, encoding="utf-8", errors="replace") as src:
                for line in src:
                    try:
                        entry = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(entry, dict):
                        continue
                    ts = str(entry.get("timestamp", ""))
                    if args.since and ts[:10] < args.since:
                        continue
                    text = prompt_text(entry)
                    if text is None or text in seen:
                        continue
                    seen.add(text)
                    fh.write(json.dumps({"project": project, "ts": ts[:10], "prompt": text}) + "\n")
    print(f"{len(seen)} distinct prompts from {len(files)} transcripts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
