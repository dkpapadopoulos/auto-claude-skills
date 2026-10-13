#!/usr/bin/env python3
"""Verb attribution census: WHICH trigger alternative earned each mandate of a skill?

A descriptive, zero-label companion to census.py. For every typed prompt in the window whose
routing block mandates --skill (the same readers, pairing and turn boundary as census.py),
every trigger regex of that skill from config/default-triggers.json is run over the
lowercased prompt text, as the hook does (`[[ "$P" =~ $trigger ]]` on the lowercased
prompt, rescanning from one past each hit, and rejecting a hit interior to a word on both
sides, as `_score_skills` does). Each trigger is split into its top-level alternatives first,
and an alternative that matches is named by its OWN source text in the config: the bare verb
for the word list ("build"), `set.?up`, `how.(should|would|could)`, `check.*(code|changes|diff)`.
Never by what it matched: the matched span of a wildcard alternative is prompt text, which
this tool must not print. A prompt can carry several; `sole` counts
prompts where exactly one alternative matched across all of the skill's triggers, which is
the population a deletion of that alternative would actually change. A mandate whose prompt
matches no alternative was not earned by the prompt's own words (chain injection, the
keyword path, or a name mention) and is counted as unattributed, never dropped.

It decides nothing. Whether a mandate was warranted needs labels; this says only how often
each alternative fires, how often it fires alone, and how often the mandated skill was then
invoked in the same turn or later in the session. Counts only; no prompt text is printed.

Exit codes: 0 counted; 2 unreadable input, bad usage, an unknown skill, or a skill with no
trigger; 3 cannot check (no counted session with a typed prompt in the window, or no mandate
for the skill in it).

Usage:
  verbs.py --skill NAME --since ISO8601 [--until ISO8601] [--min-version X.Y.Z]
           [--projects DIR] [--config FILE]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import glob  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "real-prompt-replay"))
from census import (DEFAULT_MIN_VERSION, block_text, is_text_input, mandates_of, pair_block,  # noqa: E402
                    parse_version, read_session, skill_uses, ts_of, typed)
from extract import prompt_of  # noqa: E402

DEFAULT_CONFIG = os.path.normpath(os.path.join(HERE, "..", "..", "..", "config", "default-triggers.json"))


LEAD = "(^|[^a-z])"
TAIL = "($|[^a-z])"
EDGE = re.compile(r"[a-z0-9_.]")   # the hook's word characters for the interior-hit rule


def split_top(src):
    """Split a regex source on `|` at parenthesis depth 0 (brackets and escapes respected)."""
    parts, depth, cur, i = [], 0, [], 0
    while i < len(src):
        ch = src[i]
        if ch == "\\" and i + 1 < len(src):
            cur.append(src[i:i + 2]); i += 2; continue
        if ch == "[":
            j = src.find("]", i + 2)
            j = len(src) - 1 if j < 0 else j
            cur.append(src[i:j + 1]); i = j + 1; continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "|" and depth == 0:
            parts.append("".join(cur)); cur = []
        else:
            cur.append(ch)
        i += 1
    parts.append("".join(cur))
    return parts


def strip_outer(src):
    """The inside of one group that wraps the whole source, else None."""
    if not (src.startswith("(") and src.endswith(")")):
        return None
    depth = 0
    for i, ch in enumerate(src):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0 and i != len(src) - 1:
                return None
    return src[1:-1]


def expand(src):
    """(name, regex source) for every top-level alternative of one trigger.

    Two shapes exist in the config: an outer group of alternatives, some of which carry their
    own boundary scaffolding (`(^|[^a-z])review`), and a scaffolded word list
    (`(^|[^a-z])(build|create|...)($|[^a-z])`), whose list is expanded with the scaffolding
    kept on each word. A trigger of neither shape is one alternative. The name is the
    alternative's own source text with the scaffolding and one wrapping group removed, so a
    wildcard alternative such as `check.*(code|changes|diff)` names ITSELF, never what it
    matched: the matched span of a wildcard is prompt text."""
    inner = strip_outer(src)
    if inner is not None:
        parts = split_top(inner)
        if len(parts) > 1:
            return [(alt_name(p), p) for p in parts]
    depth, start = 0, -1
    for i, ch in enumerate(src):
        if ch == "(":
            if depth == 0:
                start = i
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0 and start >= 0:
                body = src[start + 1:i]
                parts = split_top(body)
                if len(parts) > 1 and all(re.fullmatch(r"[a-z]+", p) for p in parts):
                    prefix, suffix = src[:start], src[i + 1:]
                    return [(p, prefix + p + suffix) for p in parts]
                start = -1
    return [(alt_name(src), src)]


def alt_name(alt):
    name = alt
    if name.startswith(LEAD):
        name = name[len(LEAD):]
    if name.endswith(TAIL):
        name = name[:-len(TAIL)]
    inner = strip_outer(name)
    return inner if inner else name


def load_triggers(path, skill):
    """[(name, compiled regex)] for every alternative of the skill's triggers; None when the
    skill is unknown; [] when it has no trigger. DOTALL because bash ERE's `.` crosses newlines."""
    with open(path, encoding="utf-8") as src:
        cfg = json.load(src)
    for entry in cfg.get("skills") or []:
        if isinstance(entry, dict) and entry.get("name") == skill:
            out = []
            for trig in entry.get("triggers") or []:
                if isinstance(trig, str):
                    out.extend((n, re.compile(s, re.DOTALL)) for n, s in expand(trig))
            return out
    return None


def hits(rx, text):
    """Whether the alternative matches the text the way the hook credits it: rescanning from
    one past each hit, as `_score_skills` does, and rejecting a hit that is interior to a word
    on BOTH sides (`hang` inside "changes"); a hit touching a word edge on either side counts."""
    pos = 0
    while pos <= len(text):
        m = rx.search(text, pos)
        if m is None:
            return False
        a, b = m.start(), m.end()
        # A scaffolded alternative (`(^|[^a-z])new($|[^a-z])`) matches its boundary characters
        # too; they are an assertion about the word's edges, not part of the hit, so the edge
        # rule is applied to the word inside them (the hook never evaluates one alternative
        # of a word list on its own, so this is the only reading under which "build new"
        # credits "new" the way the whole trigger credits it).
        while a < b and not re.match(r"[a-z0-9]", text[a]):
            a += 1
        while b > a and not re.match(r"[a-z0-9]", text[b - 1]):
            b -= 1
        if a == b:
            pos = m.start() + 1
            continue
        left_ok = a == 0 or not EDGE.match(text[a - 1])
        right_ok = b >= len(text) or not EDGE.match(text[b])
        if left_ok or right_ok:
            return True
        pos = m.start() + 1
    return False


def alternatives(patterns, text):
    """Names of every trigger alternative matching the lowercased text."""
    return {name for name, rx in patterns if hits(rx, text)}


def census(projects, since, until, min_version, skill, patterns):
    paths = sorted(glob.glob(os.path.join(projects, "*", "*.jsonl")))
    c = {"transcripts read": 0, "transcripts unreadable": 0, "sessions counted": 0,
         "sessions below version floor": 0, "sessions with unknown version": 0, "typed prompts": 0,
         "mandates": 0, "sole": 0, "unattributed": 0, "unattributed in-turn": 0, "unattributed later": 0}
    alts = {}   # name -> [mandates, sole, in-turn, later]
    for path in paths:
        try:
            entries, version = read_session(path)
        except OSError:
            c["transcripts unreadable"] += 1
            continue
        c["transcripts read"] += 1
        prompts = [prompt_of(e) for e in entries]
        stamps = [ts_of(e.get("timestamp")) for e in entries]
        in_window = [s is not None and s >= since and (until is None or s < until) for s in stamps]
        typed_idx = [i for i, p in enumerate(prompts) if typed(p) and in_window[i]]
        if not typed_idx:
            continue
        ver = parse_version(version)
        if ver is None:
            c["sessions with unknown version"] += 1
            continue
        if ver < min_version:
            c["sessions below version floor"] += 1
            continue
        c["sessions counted"] += 1
        c["typed prompts"] += len(typed_idx)
        by_uuid = {}
        for i, e in enumerate(entries):
            u = e.get("uuid")
            if isinstance(u, str) and u and u not in by_uuid:
                by_uuid[u] = i
        block_of = {}
        for i, e in enumerate(entries):
            text = block_text(e)
            if text is None or not in_window[i]:
                continue
            j = pair_block(i, by_uuid, entries, prompts)
            if j is not None and j != -1 and typed(prompts[j]):
                block_of.setdefault(j, text)
        boundaries = [i for i, p in enumerate(prompts) if p is not None or is_text_input(entries[i])]
        for i in typed_idx:
            block = block_of.get(i)
            if block is None or skill not in mandates_of(block):
                continue
            nxt = next((q for q in boundaries if q > i), len(entries))
            in_turn = any(s == skill for e in entries[i + 1:nxt] for s in skill_uses(e))
            later = (not in_turn) and any(s == skill for e in entries[nxt:] for s in skill_uses(e))
            c["mandates"] += 1
            names = alternatives(patterns, prompts[i][0].lower())
            if not names:
                c["unattributed"] += 1
                c["unattributed in-turn"] += 1 if in_turn else 0
                c["unattributed later"] += 1 if later else 0
                continue
            if len(names) == 1:
                c["sole"] += 1
            for name in names:
                row = alts.setdefault(name, [0, 0, 0, 0])
                row[0] += 1
                row[1] += 1 if len(names) == 1 else 0
                row[2] += 1 if in_turn else 0
                row[3] += 1 if later else 0
    return c, alts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--skill", required=True)
    ap.add_argument("--since", required=True)
    ap.add_argument("--until")
    ap.add_argument("--min-version", default=DEFAULT_MIN_VERSION)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--config", default=DEFAULT_CONFIG)
    args = ap.parse_args()

    since = ts_of(args.since)
    until = ts_of(args.until) if args.until else None
    if since is None or (args.until and until is None):
        print("--since/--until must be ISO-8601 timestamps", file=sys.stderr)
        return 2
    min_version = parse_version(args.min_version)
    if min_version is None:
        print(f"--min-version must be X.Y.Z, not: {args.min_version}", file=sys.stderr)
        return 2
    if not os.path.isdir(args.projects):
        print(f"cannot read projects directory: {args.projects}", file=sys.stderr)
        return 2
    if not re.fullmatch(r"[a-z][a-z0-9-]*", args.skill):
        print(f"--skill must be a bare skill name, not: {args.skill}", file=sys.stderr)
        return 2
    try:
        patterns = load_triggers(args.config, args.skill)
    except (OSError, ValueError) as exc:
        print(f"cannot read config {args.config}: {exc}", file=sys.stderr)
        return 2
    if patterns is None:
        print(f"unknown skill in {args.config}: {args.skill}", file=sys.stderr)
        return 2
    if not patterns:
        print(f"no trigger for {args.skill} in {args.config}: nothing to attribute", file=sys.stderr)
        return 2

    c, alts = census(args.projects, since, until, min_version, args.skill, patterns)
    print(f"window: {args.since} to {args.until or 'open'}; version floor {args.min_version}; skill {args.skill}; triggers {len(patterns)}")
    for key in ("transcripts read", "transcripts unreadable", "sessions counted", "sessions below version floor",
                "sessions with unknown version"):
        print(f"{key}: {c[key]}")
    if c["sessions counted"] == 0:
        print("cannot check: no session at or above the version floor has a typed prompt in the window")
        return 3
    print(f"typed prompts: {c['typed prompts']}")
    print(f"mandates for {args.skill}: {c['mandates']}")
    if c["mandates"] == 0:
        print(f"cannot check: no typed prompt in the window carried a mandate for {args.skill}")
        return 3
    print(f"prompts with exactly one alternative: {c['sole']}")
    print(f"unattributed (no alternative matched): {c['unattributed']}")
    print(f"unattributed in-turn: {c['unattributed in-turn']} later: {c['unattributed later']}")
    for name in sorted(alts, key=lambda n: (-alts[n][0], n)):
        m, s, i, l = alts[name]
        print(f"alt: {name} mandates={m} sole={s} in-turn={i} later={l}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(2)
    except Exception as exc:  # noqa: BLE001 — an uncaught failure is never a verdict's code
        print(f"verbs.py: {exc.__class__.__name__}: {exc}", file=sys.stderr)
        sys.exit(2)
