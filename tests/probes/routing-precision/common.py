"""Shared reading code for the routing-precision probe (#333).

A session is one top-level transcript. The activation hook's shadow record names the
session by its token, `session-<transcript basename>`, so a record is joined to the prompt
it describes by session and by time.
"""
import datetime
import glob
import json
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "real-prompt-replay"))
from extract import iter_entries, open_private, prompt_of, refuse_repo_path, text_of  # noqa: E402,F401

JOIN_WINDOW_S = 15          # a record is written by the hook that ran for the prompt
PUSH_WORDS = ("git push", "gh pr merge")
GATED = ("requesting-code-review", "verification-before-completion")


def ts_of(value):
    """Seconds since the epoch for an ISO-8601 timestamp, or None."""
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def rec_ts(record):
    """A shadow record's time. read_shadow only returns records whose ts parses."""
    return ts_of(record.get("ts")) or 0.0


def read_shadow(path):
    """Every well-formed shadow record; malformed ones are counted, never guessed at.

    `path` is the hook's record DIRECTORY (one small JSON file per record) or, for
    constructed data, a single JSONL file. Records come back oldest first.
    """
    if os.path.isdir(path):
        lines = []
        for name in sorted(os.listdir(path)):
            if name.endswith(".json"):
                try:
                    with open(os.path.join(path, name), encoding="utf-8", errors="replace") as src:
                        lines.append(src.read())
                except OSError:
                    lines.append("")
    else:
        with open(path, encoding="utf-8", errors="replace") as src:
            lines = [line for line in src if line.strip()]
    records, bad = [], 0
    for line in lines:
        try:
            rec = json.loads(line)
        except ValueError:
            bad += 1
            continue
        if not isinstance(rec, dict) or ts_of(rec.get("ts")) is None or not rec.get("session") or not rec.get("skill"):
            bad += 1
            continue
        records.append(rec)
    records.sort(key=rec_ts)
    return records, bad


def transcript_for(projects, session):
    """The transcript file of a session token, or None. Only top-level transcripts."""
    name = session[len("session-"):] if session.startswith("session-") else session
    if not name or "/" in name or name.startswith("."):
        return None
    hits = glob.glob(os.path.join(projects, "*", name + ".jsonl"))
    return hits[0] if len(hits) == 1 else None


def skill_uses(content):
    """Bare names of skills invoked in one assistant message's content."""
    out = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "Skill":
                name = str((block.get("input") or {}).get("skill") or "")
                if name:
                    out.append(name.split(":")[-1])
    return out


def tool_names(content):
    out = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name"):
                out.append(str(block["name"]))
    return out


def push_commands(content):
    """tool_use ids of Bash calls that push or merge."""
    out = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "Bash":
                cmd = str((block.get("input") or {}).get("command") or "")
                if any(w in cmd for w in PUSH_WORDS):
                    out.append(str(block.get("id") or ""))
    return out


def gate_denials(content):
    """tool_use ids whose result is a push-gate denial."""
    out = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                body = block.get("content")
                if isinstance(body, list):
                    body = " ".join(str(b.get("text") or "") for b in body if isinstance(b, dict))
                if isinstance(body, str) and "PUSH GATE" in body:
                    out.append(str(block.get("tool_use_id") or ""))
    return out


def read_session(path):
    """The session as a list of turns. A turn starts at a typed prompt and holds everything
    the assistant did until the next one.

    Returns (started_at, turns). Each turn: ts, text, source, prev_assistant (the last
    assistant text BEFORE the prompt), skills, tools, pushes, denied (ids of denied pushes).
    """
    started, turns, last_text = None, [], None
    for entry in iter_entries(path):
        if entry.get("isSidechain"):
            continue
        when = ts_of(entry.get("timestamp"))
        if started is None and when is not None:
            started = when
        if entry.get("type") == "assistant":
            content = (entry.get("message") or {}).get("content")
            text = text_of(content)
            if text:
                last_text = text
            if turns:
                turns[-1]["skills"] += skill_uses(content)
                turns[-1]["tools"] += tool_names(content)
                turns[-1]["pushes"] += push_commands(content)
            continue
        found = prompt_of(entry)
        if found:
            turns.append({"ts": when, "text": found[0], "source": found[1], "prev_assistant": last_text,
                          "skills": [], "tools": [], "pushes": [], "denied": []})
            last_text = None
            continue
        if entry.get("type") == "user" and turns:
            turns[-1]["denied"] += gate_denials((entry.get("message") or {}).get("content"))
    return started, turns


def typed(turn):
    return turn["source"] != "sdk" and not turn["text"].lstrip().startswith("<")


def join(record, turns):
    """Index of the turn a shadow record describes, or None.

    The hook writes its record while handling the prompt, so the prompt is the LATEST typed
    one that is not after the record and is no more than the window before it. The record's
    time is truncated to whole seconds, so "not after" is "strictly less than the record's
    second plus one": a prompt typed at 10.7 s whose record says 10 s still joins, and one
    typed at 11.3 s does not. None when nothing qualifies — reported, never papered over.
    """
    when = rec_ts(record)
    best = None
    for i, turn in enumerate(turns):
        if turn["ts"] is None or not typed(turn):
            continue
        if turn["ts"] < when + 1.0 and when - turn["ts"] <= JOIN_WINDOW_S:
            if best is None or turn["ts"] >= turns[best]["ts"]:
                best = i
    return best
