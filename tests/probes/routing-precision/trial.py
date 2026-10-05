#!/usr/bin/env python3
"""Read the sticky-repeat randomized trial (#333, stage B).

In trial mode the hook hides sticky repeats in half the sessions, chosen by the session
token and fixed for the session. This compares the two arms on what the rule could damage:
whether the gated steps (code review, verification) still get done.

UNIT: an OBLIGATION = (session, gated skill) for which the hook wrote at least one record
that the rule would hide, in a session that started at or after --since and ran in trial
mode. Every obligation counts, including in sessions that never tried to push: dropping
those would hide work that stalled.

For each arm it reports obligations, how many were completed (the skill was invoked at or
after the first would-hide record), how many were completed before the session's first push
or merge attempt (by the order the assistant issued them, also inside one turn), how many
sessions had their first push attempt denied by the push gate, turns from the first
would-hide record to completion, and the block text hidden.

DENOMINATORS, fixed here: completion is over obligations that were joined to a prompt (an
unjoined one is counted and printed, and counts toward neither rate nor the floor). The
denied-first-push rate is over ALL eligible sessions in the arm, including those that never
tried to push.

KNOWN NOISE: a push is any Bash command containing "git push" or "gh pr merge", and a
denial is any result of such a command containing "PUSH GATE". In a repository whose own
tests and fixtures contain those words, that over-counts in both arms alike.

It prints the pre-registered reading of those numbers. It does not flip anything. The two
comparisons are done in whole numbers: at twenty obligations an arm, ten points is exactly
two obligations, and a floating-point subtraction decides that boundary by rounding.

Usage:
  trial.py --shadow-log FILE --since ISO8601 [--projects DIR]
"""
import sys

sys.dont_write_bytecode = True

import argparse  # noqa: E402
import collections  # noqa: E402
import os  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import GATED, RULE_VERSION, join, read_session, read_shadow, rec_ts, transcript_for, ts_of  # noqa: E402

THRESHOLDS = {
    "min_obligations_per_arm": 20,     # fewer in either arm is INCONCLUSIVE
    "max_completion_drop": 0.10,       # hide arm may complete at most this much less (absolute)
    "max_denied_first_push_rise": 0.10,  # and be denied on first push at most this much more (absolute)
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shadow-log", required=True)
    ap.add_argument("--since", required=True)
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    args = ap.parse_args()
    since = ts_of(args.since)
    if since is None:
        print(f"not an ISO-8601 timestamp: {args.since}", file=sys.stderr)
        return 2

    records, bad = read_shadow(args.shadow_log)
    by_session = collections.defaultdict(list)
    for rec in records:
        if rec.get("mode") == "trial" and rec.get("rule_version") == RULE_VERSION and rec_ts(rec) >= since:
            by_session[rec["session"]].append(rec)

    arms = {a: collections.Counter() for a in ("show", "hide")}
    turns_to_done = {"show": [], "hide": []}
    skipped = collections.Counter()
    for sid, recs in sorted(by_session.items()):
        arm_values = {r.get("arm") for r in recs}
        if len(arm_values) != 1 or next(iter(arm_values)) not in arms:
            skipped["session with no single arm"] += 1
            continue
        arm = next(iter(arm_values))
        path = transcript_for(args.projects, sid)
        if not path:
            skipped["no transcript"] += 1
            continue
        started, turns = read_session(path)
        if started is None or started < since:
            skipped["session started before the trial"] += 1
            continue
        eligible = [r for r in recs if r.get("would_hide")]
        if not eligible:
            skipped["session with nothing the rule would hide"] += 1
            continue
        arms[arm]["sessions"] += 1
        arms[arm]["rows the rule would hide"] += len(eligible)
        arms[arm]["block characters hidden"] += sum(int(r.get("block_chars") or 0) for r in eligible if r.get("hidden_by_rule"))
        events = [e for t in turns for e in t["events"]]
        first_push_seq = next((q for q, kind, _ in events if kind == "push"), None)
        first_push_turn = next((i for i, t in enumerate(turns) if t["pushes"]), None)
        if first_push_turn is None:
            arms[arm]["sessions with no push attempt"] += 1
        elif set(turns[first_push_turn]["pushes"][:1]) & set(turns[first_push_turn]["denied"]):
            arms[arm]["sessions whose first push attempt was denied"] += 1
        for skill in GATED:
            mine = [r for r in eligible if r["skill"] == skill]
            if not mine:
                continue
            at = join(min(mine, key=rec_ts), turns)
            if at is None:
                arms[arm]["obligations not joined to a prompt"] += 1
                continue
            arms[arm]["obligations"] += 1
            done = next((i for i in range(at, len(turns)) if skill in turns[i]["skills"]), None)
            if done is None:
                arms[arm]["obligations never completed"] += 1
                continue
            arms[arm]["obligations completed"] += 1
            turns_to_done[arm].append(done - at)
            done_seq = next(q for i in range(at, len(turns)) for q, kind, value in turns[i]["events"]
                            if kind == "skill" and value == skill)
            if first_push_seq is None or done_seq < first_push_seq:
                arms[arm]["obligations completed before the first push attempt"] += 1

    print(f"shadow records read: {len(records)} ({bad} malformed lines skipped)")
    for name, n in skipped.items():
        print(f"  skipped: {n} {name}")
    names = ["sessions", "rows the rule would hide", "block characters hidden", "obligations", "obligations completed",
             "obligations completed before the first push attempt", "obligations never completed",
             "obligations not joined to a prompt", "sessions with no push attempt",
             "sessions whose first push attempt was denied"]
    print(f"\n{'':54s} {'show':>8s} {'hide':>8s}")
    for name in names:
        print(f"{name:54s} {arms['show'][name]:8d} {arms['hide'][name]:8d}")
    for arm in ("show", "hide"):
        got = sorted(turns_to_done[arm])
        med = got[len(got) // 2] if got else None
        print(f"median turns from first would-hide record to completion, {arm}: {med if med is not None else 'n/a'}")

    T = THRESHOLDS

    def rate(arm, name, denom):
        return (arms[arm][name] / arms[arm][denom]) if arms[arm][denom] else 0.0

    def within(a_num, a_den, b_num, b_den, limit):
        """a_num/a_den - b_num/b_den <= limit, in whole numbers (limit is hundredths)."""
        hundredths = round(limit * 100)
        return 100 * (a_num * b_den - b_num * a_den) <= hundredths * a_den * b_den

    c_show, c_hide = rate("show", "obligations completed", "obligations"), rate("hide", "obligations completed", "obligations")
    d_show = rate("show", "sessions whose first push attempt was denied", "sessions")
    d_hide = rate("hide", "sessions whose first push attempt was denied", "sessions")
    if min(arms["show"]["obligations"], arms["hide"]["obligations"]) < T["min_obligations_per_arm"]:
        print(f"\nREADING: INCONCLUSIVE — {arms['show']['obligations']} / {arms['hide']['obligations']} obligations (need {T['min_obligations_per_arm']} per arm)")
        return 3
    drop_ok = within(arms["show"]["obligations completed"], arms["show"]["obligations"],
                     arms["hide"]["obligations completed"], arms["hide"]["obligations"], T["max_completion_drop"])
    rise_ok = within(arms["hide"]["sessions whose first push attempt was denied"], arms["hide"]["sessions"],
                     arms["show"]["sessions whose first push attempt was denied"], arms["show"]["sessions"],
                     T["max_denied_first_push_rise"])
    ok = drop_ok and rise_ok
    print(f"\ncompletion: show {c_show:.1%}, hide {c_hide:.1%} (limit: at most {T['max_completion_drop']:.0%} lower) -> {'ok' if drop_ok else 'OVER'}")
    print(f"first push denied: show {d_show:.1%}, hide {d_hide:.1%} (limit: at most {T['max_denied_first_push_rise']:.0%} higher) -> {'ok' if rise_ok else 'OVER'}")
    print("READING: " + ("NO LARGE HARM SEEN — the owner may consider making suppression the default"
                         if ok else "HARM — the rule goes back to shadow or is removed"))
    print("  With this many obligations the comparison can only catch a large difference;")
    print("  it is a tripwire against serious harm, not evidence that there is none.")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as err:
        # An input that cannot be read is not a verdict. Exit 2, never 1: 1 is a decision.
        print(f"cannot read the inputs: {type(err).__name__}: {err}", file=sys.stderr)
        sys.exit(2)
