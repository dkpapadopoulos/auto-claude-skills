#!/usr/bin/env python3
"""Extract the distinct prompts from local Claude Code transcripts, labelled by source.

The output holds your own prompt text, so it must never land in a git repository: an output
path inside one, or one that git cannot vouch for, is refused (exit 2). Write it to a
temporary directory.

A prompt is a top-level user entry whose content is text, or a `queued_command` attachment
(a prompt typed while a turn was running). Each is labelled from the transcript's own
provenance fields, never from its wording:
  human        origin.kind == "human" (typed, an accepted suggestion, or queued);
  sdk          promptSource == "sdk" or an sdk-* entrypoint (scripts and pipelines);
  <kind>       any other origin.kind (task-notification, peer, auto-continuation, ...);
  unlabelled   no provenance fields (relays from other sessions). Not assumed human.
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
import re
import subprocess
import sys

SKIP_PREFIX = (
    "<task-notification>", "This session is being continued", "Base directory for this skill",
    "<command-", "<local-command", "[Request interrupted", "<system-reminder>",
    "<bash-", "<user-prompt-submit-hook>",
)
RANK = {"human": 0, "unlabelled": 1, "sdk": 2}


NOT_A_REPO = "not a git repository (or any of the parent directories)"
GIT_ENV_DROP = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_CEILING_DIRECTORIES",
                "GIT_DISCOVERY_ACROSS_FILESYSTEM")


def repo_holding(path):
    """(repository, reason) for `path` or its nearest existing ancestor.

    repository is the git dir when git says the directory is inside a repository (a work
    tree or a .git directory); reason is set when git could not answer, which the caller
    must treat as a refusal. (None, None) only when git searched every parent directory and
    found no repository: a broken .git file or a filesystem boundary also print "not a git
    repository", but they stop the search early, so they are refusals too.
    """
    probe = os.path.realpath(path)
    while not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            return None, f"no existing ancestor of {path}"
        probe = parent
    env = {k: v for k, v in os.environ.items() if k not in GIT_ENV_DROP}
    env["LC_ALL"] = "C"
    try:
        res = subprocess.run(["git", "-C", probe, "rev-parse", "--absolute-git-dir"],
                             capture_output=True, text=True, timeout=10, env=env)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"git is unavailable ({exc.__class__.__name__})"
    if res.returncode == 0:
        return res.stdout.strip() or probe, None
    if NOT_A_REPO in res.stderr:
        return None, None
    return None, "git could not tell: " + (res.stderr.strip().splitlines() or ["no output"])[-1]


def refuse_repo_path(path):
    """Print a refusal and return True unless git confirms `path` is outside every repository."""
    repo, reason = repo_holding(path)
    if repo:
        print(f"refusing to write prompt text inside a git repository ({repo}): {path}", file=sys.stderr)
        return True
    if reason:
        print(f"refusing to write: cannot check that {path} is outside a git repository: {reason}",
              file=sys.stderr)
        return True
    return False


def open_private(path):
    """Open `path` for writing as mode 0600 (an existing file is reset to 0600 and
    truncated), refusing a symlink or a hard link as the file.

    Parent directories can still be swapped between the check and the open: the guard
    protects against mistakes, not against a concurrent attacker on your own machine."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    if os.fstat(fd).st_nlink > 1:
        os.close(fd)
        raise OSError(f"refusing to write through a hard link: {path}")
    os.fchmod(fd, 0o600)
    os.ftruncate(fd, 0)
    return os.fdopen(fd, "w", encoding="utf-8")


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
    if entry.get("type") == "attachment" and isinstance(att, dict) and not att.get("isMeta") \
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
            ok = re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) and datetime.date.fromisoformat(value)
        except ValueError:
            ok = False
        if not ok:
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
    try:
        fh = open_private(args.out)
    except OSError as exc:
        print(f"refusing to write: {exc}", file=sys.stderr)
        return 2
    with fh:
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
