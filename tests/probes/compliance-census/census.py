#!/usr/bin/env python3
"""In-turn compliance census: do the routing block's MUST INVOKE mandates move behaviour?

Reads the owner's own Claude Code transcripts (top-level sessions only,
<projects>/<p>/<session>.jsonl) and counts, with NO labels and NO prompt text in its output:

  typed prompts            a user entry the transcript labels origin "human" whose text does
                           not start with "<" (the same rule as routing-precision/rows.py)
  blocks                   the activation hook's UserPromptSubmit hook_additional_context
                           attachment containing "SKILL ACTIVATION", paired to the input it
                           answered by walking parentUuid (as real-prompt-replay/routed.py does)
  mandates                 each distinct "<skill> MUST INVOKE" on the block's verdict line:
                           "Evaluate: **Phase: [X]** | ..." in the compact formats, or
                           "**Phase: [PHASE]** | ..." in the full first-prompt format (the
                           same words in prose elsewhere are not a mandate)
  obeyed in-turn           a Skill tool_use whose bare name equals the mandate, in the entries
                           after the prompt and before the next text input of ANY source: a
                           prompt, a queued prompt, or a notification wrapper (a tool result,
                           a skill-load meta entry or a sidechain entry does not end a turn)
  obeyed later             the same, anywhere later in the session
  gating invocations       requesting-code-review / verification-before-completion invoked in
                           a typed turn: "routed" when that turn's block lists the skill on
                           its verdict line, "unrouted" otherwise (prose mentions, or no
                           block at all)
  version floor            a session counts only when its SessionStart hook output or a
                           skill-load entry names an installed plugin version at or above
                           --min-version; sessions below it, or with no evidence, are counted
                           out separately and never assumed current

Collection is registered by COUNT: it closes at the --close-at'th mandate by time, or on
--cap-date, whichever is first (README.md is the pre-registration). While open, the last
line says so and no verdict is printed. When closed by count, the verdict reads exactly the
first --close-at mandates and reports how many later ones it did not read; when closed by
date, the window is capped at the cap date even when read later. The verdict line carries
the one-sided exact Fisher tail of the observed in-turn count against --control (K/N, the
baseline week), and the registered reading rule. A window that closes with zero mandates is
cannot-check (exit 3), never a verdict.

Exit codes: 0 counted; 2 unreadable projects directory, bad usage, or an instrument fault
(blocks exist in the window and not one pairs with any input: the transcript format has
changed, and zeros would read as "nobody obeyed"); 3 cannot check (no transcript, or no
session at or above the floor with a typed prompt in the window). A single transcript that
cannot be read is counted ("transcripts unreadable") and skipped. A verdict is never an exit
code.

Usage:
  census.py --since ISO8601 [--until ISO8601] [--projects DIR] [--min-version X.Y.Z]
            [--control K/N] [--close-at N] [--cap-date YYYY-MM-DD] [--today YYYY-MM-DD]
  census.py --self-test-p K N --control K/N      # print the tail for K of N and exit
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import datetime  # noqa: E402
import glob  # noqa: E402
import math  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402
import statistics  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "real-prompt-replay"))
from extract import iter_entries, prompt_of, text_of  # noqa: E402
from routed import install_version  # noqa: E402

MANDATE_RE = re.compile(r"(?<![A-Za-z0-9-])([a-z][a-z0-9-]*) MUST INVOKE")
# The hook's verdict line: "Evaluate: **Phase: [X]** | ..." in the compact formats, and
# "  **Phase: [PHASE]** | ..." (no prefix) in the full format it renders on a session's
# first prompt when three or more skills route. Prose elsewhere in the block also says
# "MUST INVOKE" ("Process skills marked MUST INVOKE are mandatory") and is never a mandate.
VERDICT_RE = re.compile(r"^\s*(?:Evaluate:\s*)?\*\*Phase: \[")
VERSION_RE = re.compile(r"/auto-claude-skills/(\d+\.\d+\.\d+)(?=/|\s|$)")
GATED = ("requesting-code-review", "verification-before-completion")
DEFAULT_MIN_VERSION = "3.95.8"      # first build carrying PR #349 (the cut) and PR #350
DEFAULT_CLOSE_AT = 46               # pre-registered: mandates rendered, not days
DEFAULT_CAP_DATE = "2026-11-09"     # pre-registered cap, four weeks from the data start
DEFAULT_CONTROL = "2/35"            # this instrument's read of 2026-10-05..10-12, every version: 2 of 35


def ts_of(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def parse_version(text):
    found = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", str(text or "").strip())
    return tuple(int(g) for g in found.groups()) if found else None


def parse_control(text):
    found = re.fullmatch(r"(\d+)/(\d+)", str(text or "").strip())
    if not found:
        return None
    k, n = int(found.group(1)), int(found.group(2))
    return (k, n) if k <= n else None


def one_sided_p(k, n, c, m):
    """P(X >= k) for the 2x2 table [[k, n-k], [c, m-c]] under the hypergeometric null:
    the chance of at least k obeyed among n census mandates when k+c of n+m were obeyed."""
    successes, total = k + c, n + m
    if n <= 0 or total <= 0:
        return 1.0
    denom = math.comb(total, n)
    tail = sum(math.comb(successes, j) * math.comb(total - successes, n - j)
               for j in range(k, min(successes, n) + 1))
    return tail / denom


def block_text(entry):
    att = entry.get("attachment")
    if entry.get("type") != "attachment" or not isinstance(att, dict):
        return None
    if att.get("type") != "hook_additional_context" or att.get("hookEvent") != "UserPromptSubmit":
        return None
    content = att.get("content")
    if isinstance(content, list):
        content = "\n".join(c for c in content if isinstance(c, str))
    if not isinstance(content, str) or "SKILL ACTIVATION" not in content:
        return None
    return content


def mandates_of(block):
    out = []
    for line in block.splitlines():
        if VERDICT_RE.match(line):
            for name in MANDATE_RE.findall(line):
                if name not in out:
                    out.append(name)
    return out


ROUTED_RE = re.compile(r"(?<![A-Za-z0-9-])([a-z][a-z0-9-]*) (?:MUST INVOKE|YES/NO|INVOKE WHEN)")


def routed_names(block):
    """Every skill the block's verdict line lists, mandated or not. A skill named only in
    prose elsewhere in the block was not routed."""
    out = set()
    for line in block.splitlines():
        if VERDICT_RE.match(line):
            out.update(ROUTED_RE.findall(line))
    return out


def skill_uses(entry):
    if entry.get("type") != "assistant":
        return []
    msg = entry.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    out = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "Skill":
                name = str((block.get("input") or {}).get("skill") or "")
                if name:
                    out.append(name.split(":")[-1])
    return out


def typed(prompt):
    return prompt is not None and prompt[1] == "human" and not prompt[0].startswith("<")


def read_session(path):
    """Entries, their prompts, and the plugin version evidenced (None when none)."""
    entries = list(iter_entries(path))
    version = None
    for entry in entries:
        found = install_version(entry, VERSION_RE)
        if found and version is None:
            version = found
    return entries, version


def is_text_input(entry):
    """A user entry carrying text (a prompt, or a wrapper the extractor skips, such as a
    notification), as opposed to a tool result. Walking stops at either; only the first
    is an input a block can have answered. A meta entry (the harness injecting a skill
    body: "Base directory for this skill: ...") or a sidechain entry is not an input and
    does not end a turn."""
    if entry.get("type") != "user" or entry.get("isMeta") or entry.get("isSidechain"):
        return False
    msg = entry.get("message")
    return text_of(msg.get("content") if isinstance(msg, dict) else msg) is not None


def pair_block(index, by_uuid, entries, prompts):
    """The index of the input entry a block answered, following parentUuid; None when the
    chain reaches no entry; -1 when it reaches a user entry that is a tool result. An input
    the extractor skipped (a notification wrapper) is returned like a prompt: its prompt is
    None, and the caller counts it as a non-typed input."""
    seen = set()
    parent = entries[index].get("parentUuid")
    while isinstance(parent, str) and parent and parent not in seen:
        seen.add(parent)
        j = by_uuid.get(parent)
        if j is None:
            return None
        if prompts[j] is not None or is_text_input(entries[j]):
            return j
        if entries[j].get("type") == "user":
            return -1
        parent = entries[j].get("parentUuid")
    return None


def census(projects, since, until, min_version):
    paths = sorted(glob.glob(os.path.join(projects, "*", "*.jsonl")))
    c = {"transcripts read": 0, "transcripts unreadable": 0, "sessions counted": 0,
         "sessions below version floor": 0, "sessions with unknown version": 0, "typed prompts": 0,
         "typed prompts with a block": 0, "inputs with a block that are not typed prompts": 0,
         "blocks unpaired": 0, "mandates rendered": 0, "obeyed in-turn": 0, "obeyed later in session": 0,
         "routed": 0, "unrouted": 0}
    by_skill = {}
    sizes = []
    mandates = []           # (timestamp, skill, obeyed in-turn) for every mandate, across sessions
    blocks_in_window = 0
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
        # Each block in the window, paired to its input.
        block_of = {}
        for i, e in enumerate(entries):
            text = block_text(e)
            if text is None or not in_window[i]:
                continue
            blocks_in_window += 1
            j = pair_block(i, by_uuid, entries, prompts)
            if j is None or j == -1:
                c["blocks unpaired"] += 1
            elif typed(prompts[j]):
                block_of.setdefault(j, text)
            else:
                c["inputs with a block that are not typed prompts"] += 1
        # Turns: from a typed prompt to the next input of any source: a prompt, or a text
        # input the extractor skips (a notification wrapper). A tool result is not an input.
        prompt_positions = [i for i, p in enumerate(prompts) if p is not None or is_text_input(entries[i])]
        for i in typed_idx:
            nxt = next((q for q in prompt_positions if q > i), len(entries))
            in_turn = [s for e in entries[i + 1:nxt] for s in skill_uses(e)]
            later = [s for e in entries[nxt:] for s in skill_uses(e)]
            block = block_of.get(i)
            if block is not None:
                c["typed prompts with a block"] += 1
                sizes.append(len(block.encode("utf-8")))
                for name in mandates_of(block):
                    row = by_skill.setdefault(name, [0, 0, 0])
                    row[0] += 1
                    c["mandates rendered"] += 1
                    mandates.append((stamps[i] or 0.0, name, name in in_turn))
                    if name in in_turn:
                        row[1] += 1
                        c["obeyed in-turn"] += 1
                    elif name in later:
                        row[2] += 1
                        c["obeyed later in session"] += 1
            listed = routed_names(block) if block is not None else set()
            for name in in_turn:
                if name in GATED:
                    c["routed" if name in listed else "unrouted"] += 1
    mandates.sort(key=lambda m: m[0])
    return c, by_skill, sizes, blocks_in_window, mandates


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", help="ISO-8601 start of the window (inclusive)")
    ap.add_argument("--until", help="ISO-8601 end of the window (exclusive); default open")
    ap.add_argument("--min-version", default=DEFAULT_MIN_VERSION)
    ap.add_argument("--control", default=DEFAULT_CONTROL, help="K/N obeyed in the baseline week")
    ap.add_argument("--close-at", type=int, default=DEFAULT_CLOSE_AT)
    ap.add_argument("--cap-date", default=DEFAULT_CAP_DATE)
    ap.add_argument("--today", help=argparse.SUPPRESS)
    ap.add_argument("--self-test-p", nargs=2, type=int, metavar=("K", "N"), help="print the tail for K of N and exit")
    args = ap.parse_args()

    control = parse_control(args.control)
    if control is None:
        print(f"--control must be K/N with K <= N, not: {args.control}", file=sys.stderr)
        return 2
    if args.self_test_p:
        k, n = args.self_test_p
        if k < 0 or n <= 0 or k > n:
            print("--self-test-p needs 0 <= K <= N, N > 0", file=sys.stderr)
            return 2
        print(f"p={one_sided_p(k, n, control[0], control[1]):.4f} (one-sided, {k} of {n} against {control[0]}/{control[1]})")
        return 0
    if not args.since:
        print("--since is required", file=sys.stderr)
        return 2
    since = ts_of(args.since)
    until = ts_of(args.until) if args.until else None
    if since is None or (args.until and until is None):
        print("--since/--until must be ISO-8601 timestamps", file=sys.stderr)
        return 2
    min_version = parse_version(args.min_version)
    if min_version is None:
        print(f"--min-version must be X.Y.Z, not: {args.min_version}", file=sys.stderr)
        return 2
    today = args.today or datetime.date.today().isoformat()
    cap_ok = ts_of(args.cap_date + "T00:00:00+00:00") is not None and ts_of(today + "T00:00:00+00:00") is not None
    if not cap_ok or args.close_at <= 0:
        print("--cap-date and --today must be dates; --close-at must be positive", file=sys.stderr)
        return 2
    if not os.path.isdir(args.projects):
        print(f"cannot read projects directory: {args.projects}", file=sys.stderr)
        return 2

    # Closing by date caps the window at the cap date: a read after it must not count what
    # was rendered later, or the result would depend on when the owner happened to read.
    by_date = today >= args.cap_date
    cap_ts = ts_of(args.cap_date + "T00:00:00+00:00")
    if by_date and cap_ts is not None and (until is None or until > cap_ts):
        until = cap_ts
    c, by_skill, sizes, blocks_in_window, mandates = census(args.projects, since, until, min_version)
    until_text = args.until or "open"
    if by_date:
        until_text = f"{args.cap_date} (cap date reached)"
    print(f"window: {args.since} to {until_text}; version floor {args.min_version}")
    for key in ("transcripts read", "transcripts unreadable", "sessions counted", "sessions below version floor",
                "sessions with unknown version"):
        print(f"{key}: {c[key]}")
    if c["transcripts read"] == 0 or c["sessions counted"] == 0:
        print("cannot check: no session at or above the version floor has a typed prompt in the window")
        return 3
    if blocks_in_window > 0 and c["blocks unpaired"] == blocks_in_window:
        print(f"instrument fault: {blocks_in_window} block(s) in the window and not one pairs with any input; "
              "the transcript format may have changed (see pair_block). Nothing counted.")
        return 2
    for key in ("typed prompts", "typed prompts with a block", "inputs with a block that are not typed prompts",
                "blocks unpaired", "mandates rendered", "obeyed in-turn", "obeyed later in session"):
        print(f"{key}: {c[key]}")
    print(f"gating invocations in typed turns: routed={c['routed']} unrouted={c['unrouted']}")
    if sizes:
        print(f"block bytes: median={int(statistics.median(sizes))} mean={int(statistics.mean(sizes))} (over typed prompts with a block)")
    else:
        print("block bytes: none")
    for name in sorted(by_skill):
        row = by_skill[name]
        print(f"by skill: {name} mandates={row[0]} in-turn={row[1]} later={row[2]}")

    total = c["mandates rendered"]
    if total == 0 and by_date:
        print(f"cannot check: the window closed on {args.cap_date} with no mandate rendered; "
              "a verdict over zero mandates is not a verdict")
        return 3
    if total >= args.close_at:
        # The window closed at the close-at'th mandate by time. Anything rendered after it is
        # reported in the table above and never read: reading it would be optional stopping.
        read = mandates[:args.close_at]
        unread = total - len(read)
        tail = f"; {unread} later mandate{'s' if unread != 1 else ''} not read" if unread else ""
        print(f"collection: CLOSED (by count: {len(read)} of {args.close_at} mandates{tail})")
    elif by_date:
        read = mandates
        print(f"collection: CLOSED (by date {args.cap_date}; {total} of {args.close_at} mandates)")
    else:
        print(f"collection: OPEN ({total} of {args.close_at} mandates; closes at {args.close_at} or on {args.cap_date}). Do not read a verdict yet.")
        return 0
    n, k = len(read), sum(1 for m in read if m[2])
    p = one_sided_p(k, n, control[0], control[1])
    if p < 0.05:
        reading = "display moves behaviour; keep the display path and PR #350's line only if routed gating invocations rose"
    elif k <= 2:
        reading = "no evidence that display moves behaviour; close the display path as cost-saving only and stop display proposals"
    else:
        reading = "inconclusive; extend once by one week, then read again"
    print(f"verdict: {k} obeyed in-turn of {n} mandates against control {control[0]}/{control[1]}: p={p:.4f}; {reading}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(2)
    except Exception as exc:  # noqa: BLE001 — an uncaught failure is never a verdict's code
        print(f"census.py: {exc.__class__.__name__}: {exc}", file=sys.stderr)
        sys.exit(2)
