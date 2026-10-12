#!/bin/bash
# compaction-pairing.sh — does every compaction get a recovery?
#
# Reads ~/.claude/.compact-events.log (or the file given as $1), written by
# hooks/pre-compact-hook.sh (one `<ts> trigger=auto|manual ... path=<jsonl>` line
# per compaction), hooks/compact-recovery-hook.sh (`<ts> event=post_compact ...
# path=<jsonl>`, the SessionStart(compact) recovery) and
# hooks/compact-recovery-prompt-hook.sh (`<ts> event=post_compact_prompt
# trigger=...`, the prompt-carrier recovery, which carries no path).
#
# Why it exists: the prompt carrier was added on the premise that auto
# compaction had stopped emitting SessionStart(compact). The log says the event
# pairs with compactions again in almost every case (snapshot 2026-10-12, Sep
# 2026: 11 of 11; Oct: 9 of 10, the carrier recovered the tenth). Whether the
# carrier can be retired is a question this reader answers from evidence rather
# than memory. A carrier recovery is logged only when SessionStart did not
# consume the marker first, so the per-month `carrier=` count approximates the
# compactions the SessionStart path missed. It is a LOWER BOUND, not the exact
# count: the carrier exits without logging when it has nothing to render and
# consumes a marker older than 24h silently, and in both cases the compaction
# stays OPEN here, which the pending/unpaired output shows; it can also
# overcount when SessionStart fired but could not resolve its token (see the
# header of hooks/compact-recovery-prompt-hook.sh). The retirement rule is
# therefore three consecutive months with carrier=0 AND exit 0 with zero
# pending.
#
# Pairing: a compaction is OPEN until a recovery for its session arrives. A
# SessionStart recovery names its session and closes that one; a carrier
# recovery names none and closes the OLDEST open compaction: every SessionStart
# recovery in the log lands within ~2 minutes of its compaction, while the
# carrier fires at the next prompt, often much later, so when two sessions are
# open the older one is the one whose SessionStart is overdue and the newer
# one's is still coming (a "most recent" rule orphaned that one in review). A
# second compaction in a session that still has one open marks the earlier one
# UNPAIRED. An open compaction at the end of the log is PENDING (the session
# may still be live), never unpaired. A line that is none of the three shapes
# (a blank line excepted) is UNRECOGNISED and listed: dropping it silently
# would under-count compactions, and pre-compact-hook.sh writes trigger=unknown
# when a payload carries no trigger.
#
# Exit codes, like scripts/assert-suite-complete.sh: never two states.
#   0  every compaction paired and every line recognised
#   1  at least one unpaired compaction or unrecognised line (listed)
#   3  cannot check: no log, an empty / whitespace-only log, or a log in which
#      no compaction line was recognised. A run over zero compactions is not
#      "paired".
#
# Bash 3.2 and BSD awk; reads only; writes nothing.

LOG="${1:-${HOME}/.claude/.compact-events.log}"

if [ ! -f "${LOG}" ]; then
    printf 'cannot check: log missing: %s\n' "${LOG}"
    exit 3
fi
if ! grep -q '[^[:space:]]' "${LOG}" 2>/dev/null; then
    printf 'cannot check: log is empty: %s\n' "${LOG}"
    exit 3
fi

awk '
function month(ts) { return substr(ts, 1, 7) }
function field(line, key,   n, i, parts) {
    n = split(line, parts, " ")
    for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
    return ""
}
NF == 0 { next }
{
    ts = $1
    ev = field($0, "event"); tr = field($0, "trigger"); p = field($0, "path")
    if (ev == "post_compact") {
        m = month(ts); if (!(m in seen)) { seen[m] = 1; order[++nm] = m }
        if (p != "" && (p in open)) {
            ss[m]++
            delete open[p]; delete open_ts[p]; delete open_tr[p]
        } else {
            # a recovery for a session with no open compaction: the pre-compact hook did
            # not log, or the two hooks saw different paths. Listed, kept out of
            # sessionstart= so sessionstart + carrier never exceeds the compactions.
            stray[++nstray] = ts " (" (p == "" ? "no-path" : p) ")"
        }
    } else if (ev == "post_compact_prompt") {
        m = month(ts); if (!(m in seen)) { seen[m] = 1; order[++nm] = m }
        carrier[m]++
        # closes the OLDEST open compaction, whichever session (see header)
        best = ""; bts = ""
        for (k in open) if (bts == "" || open_ts[k] < bts) { bts = open_ts[k]; best = k }
        if (best != "") { delete open[best]; delete open_ts[best]; delete open_tr[best] }
    } else if (ev == "" && (tr == "auto" || tr == "manual")) {
        m = month(ts); if (!(m in seen)) { seen[m] = 1; order[++nm] = m }
        total++
        if (tr == "auto") auto[m]++; else manual[m]++
        if (p == "") p = "(no-path)"
        if (p in open) unpaired[++nu] = open_ts[p] " (" open_tr[p] ", " p ")"
        open[p] = 1; open_ts[p] = ts; open_tr[p] = tr
    } else {
        unrec[++nr] = $0
    }
}
END {
    if (total == 0) {
        printf "cannot check: no compaction line recognised (%d unrecognised line(s))\n", nr
        exit 3
    }
    for (i = 1; i <= nm; i++) {
        m = order[i]
        printf "%s: auto=%d manual=%d sessionstart=%d carrier=%d\n", m, auto[m]+0, manual[m]+0, ss[m]+0, carrier[m]+0
    }
    pending = 0
    for (k in open) { pending++; printf "pending: %s (%s, %s)\n", open_ts[k], open_tr[k], k }
    for (i = 1; i <= nstray; i++) printf "stray-sessionstart: %s\n", stray[i]
    for (i = 1; i <= nu; i++) printf "unpaired: %s\n", unpaired[i]
    for (i = 1; i <= nr; i++) printf "unrecognised: %s\n", unrec[i]
    if (nu > 0 || nr > 0) {
        printf "summary: %d compactions, %d unpaired, %d unrecognised, %d pending\n", total, nu, nr, pending
        exit 1
    }
    printf "summary: %d compactions, all paired, %d pending\n", total, pending
    exit 0
}
' "${LOG}"
