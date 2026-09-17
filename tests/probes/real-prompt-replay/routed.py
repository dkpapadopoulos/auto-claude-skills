#!/usr/bin/env python3
"""List the prompts the INSTALLED activation hook actually routed to one skill.

Claude Code records hook output in session transcripts as `hook_additional_context`
attachments. This keeps the UserPromptSubmit ones that carry a routing block
("SKILL ACTIVATION ...") selecting the skill (a `<name> -> Skill(<plugin>:<name>)` line), and
follows the attachment's parentUuid chain to the input it answered. A prompt is labelled by
source exactly as extract.py labels it; any other input (a notification, a wrapper) is
labelled "not-a-prompt:<source>"; a chain that reaches no input is "unpaired". Live routings
reflect whichever plugin version was installed at the time, not the current triggers;
replay.sh measures those. The hook can also select a skill by its name alone, which a
trigger replay does not model.

Also prints, for each plugin version, the first and last date it is evidenced as installed:
a skill loaded from it (the harness records "Base directory for this skill:
.../<plugin>/<version>/...") or the SessionStart hook output naming its path. Paths quoted
anywhere else do not count. A first date does not prove the version stayed installed.

Writes a JSONL of the routed inputs (source, ts, project, prompt), one line per input, which
replay.sh accepts. The output holds prompt text, so a path inside a git repository, or one
git cannot vouch for, is refused (exit 2). --since applies to the input's date.

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
from extract import open_private, prompt_of, refuse_repo_path, source_of, text_of, valid_since  # noqa: E402


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


SKILL_LOAD = "Base directory for this skill: "


def read_file(path, version_re, versions):
    """Parsed entries of one transcript; records plugin version dates on the way."""
    entries = []
    with open(path, encoding="utf-8", errors="replace") as src:
        for line in src:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict):
                continue
            entries.append(entry)
            ver = install_version(entry, version_re)
            day = str(entry.get("timestamp", ""))[:10]
            if ver and day:
                first, last = versions.get(ver, (day, day))
                versions[ver] = (min(first, day), max(last, day))
    return entries


def install_version(entry, version_re):
    """The plugin version an install-evidence entry names, else None: a skill-loading entry
    (its first line), or the SessionStart hook's own output."""
    att = entry.get("attachment")
    if entry.get("type") == "attachment" and isinstance(att, dict) \
            and att.get("type") == "hook_additional_context" and att.get("hookEvent") == "SessionStart":
        content = att.get("content")
        if isinstance(content, list):
            content = "\n".join(c for c in content if isinstance(c, str))
        found = version_re.search(content) if isinstance(content, str) else None
        return found.group(1) if found else None
    if entry.get("type") != "user":
        return None
    msg = entry.get("message")
    text = text_of(msg.get("content") if isinstance(msg, dict) else msg)
    if not isinstance(text, str) or not text.startswith(SKILL_LOAD):
        return None
    found = version_re.search(text.split("\n", 1)[0])
    return found.group(1) if found else None


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
    try:
        fh = open_private(args.out)
    except OSError as exc:
        print(f"refusing to write: {exc}", file=sys.stderr)
        return 2

    name = re.escape(args.skill)
    pattern = re.compile(r"(?m)(?:^|[\s:])" + name + r" -> Skill\(" + re.escape(args.plugin)
                         + ":" + name + r"\)")
    version_re = re.compile("/" + re.escape(args.plugin) + r"/(\d+\.\d+\.\d+)/")
    versions = {}
    counts = {}
    total = 0
    with fh:
        for path in sorted(glob.glob(os.path.join(args.projects, "*", "*.jsonl"))):
            project = os.path.basename(os.path.dirname(path))
            entries = read_file(path, version_re, versions)
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
    for ver in sorted(versions, key=lambda v: tuple(int(x) for x in v.split("."))):
        print(f"plugin {args.plugin} {ver}: {versions[ver][0]} .. {versions[ver][1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
