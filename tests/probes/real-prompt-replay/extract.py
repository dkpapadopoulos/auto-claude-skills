#!/usr/bin/env python3
"""Extract the distinct prompts from local Claude Code transcripts, labelled by source.

The output holds your own prompt text, so it must never land in a git work tree: an output
path inside one is refused (exit 2). Write it to a temporary directory.

A prompt is a top-level user entry whose content is text, or a `queued_command` attachment
(a prompt typed while a turn was running). Each is labelled from the transcript's own
provenance fields, never from its wording:
  human        origin.kind == "human" (typed, an accepted suggestion, or queued);
  sdk          promptSource == "sdk" or an sdk-* entrypoint (scripts and pipelines);
  <kind>       any other origin.kind (task-notification, peer, auto-continuation, ...);
  unlabelled   no provenance fields (older clients, teammate relays). Not assumed human.
Excluded outright: tool results, subagent transcripts (only <projects>/<p>/<session>.jsonl
is read), meta and sidechain entries, and text with a known wrapper prefix (notifications,
resumed-session summaries, injected skill bodies, command wrappers). Exact duplicates keep
their first occurrence; a prompt seen from several sources keeps the most human label.

Usage:
  extract.py --out FILE [--projects DIR] [--since YYYY-MM-DD]
"""
import argparse
import datetime
import glob
import json
import os
import subprocess
import sys

REPO_ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SKIP_PREFIX = (
    "<task-notification>", "This session is being continued", "Base directory for this skill",
    "<command-", "<local-command", "[Request interrupted", "<system-reminder>",
    "<bash-", "<user-prompt-submit-hook>",
)
RANK = {"human": 0, "unlabelled": 1, "sdk": 2}


def git_worktree_of(path):
    """Return the work tree containing `path` (or its nearest existing ancestor), else None."""
    probe = os.path.realpath(path)
    while not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            return None
        probe = parent
    try:
        res = subprocess.run(["git", "-C", probe, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return res.stdout.strip() or None if res.returncode == 0 else None


def refuse_repo_path(path):
    """Print a refusal and return True when `path` would land inside a git work tree.

    Falls back to this script's own checkout, compared case-insensitively, when git cannot
    answer (not installed, or the probe failed)."""
    tree = git_worktree_of(path)
    if not tree:
        real = os.path.realpath(path).casefold()
        if real == REPO_ROOT.casefold() or real.startswith(REPO_ROOT.casefold() + os.sep):
            tree = REPO_ROOT
    if tree:
        print(f"refusing to write prompt text inside a git work tree ({tree}): {path}", file=sys.stderr)
        return True
    return False


def text_of(content):
    """The text of a message content value, or None for tool results and non-text shapes."""
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        parts = [b.get("text") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        parts = [p for p in parts if isinstance(p, str)]
        if not parts:
            return None
        content = " ".join(parts)
    return content if isinstance(content, str) else None


def clean(text):
    text = text.strip() if isinstance(text, str) else ""
    if not text or text.startswith(SKIP_PREFIX):
        return None
    return text


def source_of(origin, entry):
    kind = origin.get("kind") if isinstance(origin, dict) else None
    if isinstance(kind, str) and kind:
        return kind
    ep = entry.get("entrypoint")
    if entry.get("promptSource") == "sdk" or (isinstance(ep, str) and ep.startswith("sdk")):
        return "sdk"
    return "unlabelled"


def prompt_of(entry):
    """(text, source) for a prompt-bearing transcript entry, else None."""
    if not isinstance(entry, dict) or entry.get("isMeta") or entry.get("isSidechain"):
        return None
    if entry.get("type") == "user":
        msg = entry.get("message")
        text = clean(text_of(msg.get("content") if isinstance(msg, dict) else msg))
        return (text, source_of(entry.get("origin"), entry)) if text else None
    att = entry.get("attachment")
    if entry.get("type") == "attachment" and isinstance(att, dict) \
            and att.get("type") == "queued_command" and att.get("commandMode", "prompt") == "prompt":
        text = clean(text_of(att.get("prompt")))
        return (text, source_of(att.get("origin") or entry.get("origin"), entry)) if text else None
    return None


def prompt_text(entry):
    """The prompt text of an entry, whatever its source (None when it carries none)."""
    got = prompt_of(entry)
    return got[0] if got else None


def valid_since(value):
    if value:
        try:
            datetime.date.fromisoformat(value)
        except ValueError:
            raise argparse.ArgumentTypeError(f"not a YYYY-MM-DD date: {value}")
    return value


def iter_entries(path):
    with open(path, encoding="utf-8", errors="replace") as src:
        for line in src:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if isinstance(entry, dict):
                yield entry


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", default="", type=valid_since)
    args = ap.parse_args()
    if refuse_repo_path(args.out):
        return 2

    files = sorted(glob.glob(os.path.join(args.projects, "*", "*.jsonl")))
    found = {}
    order = []
    for path in files:
        project = os.path.basename(os.path.dirname(path))
        for entry in iter_entries(path):
            got = prompt_of(entry)
            if not got:
                continue
            ts = str(entry.get("timestamp", ""))[:10]
            if args.since and ts < args.since:
                continue
            text, source = got
            prev = found.get(text)
            if prev is None:
                order.append(text)
            elif RANK.get(prev["source"], 3) <= RANK.get(source, 3):
                continue
            found[text] = {"project": project, "ts": ts, "source": source, "prompt": text}

    counts = {}
    with open(args.out, "w", encoding="utf-8") as fh:
        for text in order:
            rec = found[text]
            counts[rec["source"]] = counts.get(rec["source"], 0) + 1
            fh.write(json.dumps(rec) + "\n")
    print(f"prompts {len(order)}")
    print(f"transcripts {len(files)}")
    for source in sorted(counts):
        print(f"source {source}: {counts[source]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
