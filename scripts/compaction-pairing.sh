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
# pairs with auto compactions again in almost every case (Sep 2026: 11 of 11;
# Oct: 9 of 10, the carrier recovered the tenth). Whether the carrier can be
# retired is a question this reader answers from evidence rather than memory.
# A carrier recovery fires only when SessionStart did not, so the per-month
# `carrier=` count IS the number of compactions the SessionStart path missed;
# the retirement rule is three consecutive months with carrier=0.
#
# Pairing: a compaction is OPEN until a recovery for its session arrives. A
# SessionStart recovery names its session and closes that one; a carrier
# recovery names none and closes the most recent open compaction. A second
# compaction in a session that still has one open marks the earlier one
# UNPAIRED. An open compaction at the end of the log is PENDING (the session
# may still be live), never unpaired.
#
# Exit codes, like scripts/assert-suite-complete.sh: never two states.
#   0  every determined compaction paired
#   1  at least one unpaired compaction (listed)
#   3  cannot check: no log, or an empty / whitespace-only log. Never "paired".
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
{
    ts = $1
    m = month(ts)
    if (!(m in seen)) { seen[m] = 1; order[++nm] = m }
    ev = field($0, "event"); tr = field($0, "trigger"); p = field($0, "path")
    if (ev == "post_compact") {
        ss[m]++
        if (p != "" && (p in open)) { delete open[p]; delete open_ts[p]; delete open_tr[p] }
    } else if (ev == "post_compact_prompt") {
        carrier[m]++
        # closes the most recently opened compaction, whichever session
        best = ""; bts = ""
        for (k in open) if (open_ts[k] > bts) { bts = open_ts[k]; best = k }
        if (best != "") { delete open[best]; delete open_ts[best]; delete open_tr[best] }
    } else if (tr == "auto" || tr == "manual") {
        total++
        if (tr == "auto") auto[m]++; else manual[m]++
        if (p == "") p = "(no-path)"
        if (p in open) {
            unpaired[++nu] = open_ts[p] " (" open_tr[p] ", " p ")"
            if (!(ts in dummy)) {}
        }
        open[p] = 1; open_ts[p] = ts; open_tr[p] = tr
    }
}
END {
    for (i = 1; i <= nm; i++) {
        m = order[i]
        printf "%s: auto=%d manual=%d sessionstart=%d carrier=%d\n", m, auto[m]+0, manual[m]+0, ss[m]+0, carrier[m]+0
    }
    pending = 0
    for (k in open) pending++
    for (i = 1; i <= nu; i++) printf "unpaired: %s\n", unpaired[i]
    if (nu > 0) {
        printf "summary: %d compactions, %d unpaired, %d pending\n", total, nu, pending
        exit 1
    }
    printf "summary: %d compactions, all paired, %d pending\n", total, pending
    exit 0
}
' "${LOG}"
