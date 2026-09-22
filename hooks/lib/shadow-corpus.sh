#!/bin/bash
# shadow-corpus.sh — the parts of shadow-corpus measurement that are IDENTICAL
# across legs: the exact Clopper-Pearson band rule, ISO-8601 -> epoch in awk,
# and independent-episode grouping.
#
# DIAGNOSTIC ONLY. Sourced by scripts/shadow-adjudicate.sh (IMPLEMENT leg) and
# scripts/review-shadow-adjudicate.sh (REVIEW leg). Never sourced by a hook,
# never consulted by hooks/openspec-guard.sh, and deliberately EXCLUDED from
# _GATE_ENFORCE_LIBS — same posture as implement-shadow.sh and review-shadow.sh.
#
# WHY THIS FILE EXISTS. Two legs decide a deny-flip off two pre-registrations
# that share one method. Re-deriving the band rule or the episode denominator
# per leg is how this repo has repeatedly shipped two implementations of one
# rule that then drifted (#131/#133, and the producer/consumer version pin that
# blacked out the IMPLEMENT corpus). The leg-SPECIFIC parts — which log, which
# schema, what `false_block` means, what the floor is — deliberately stay in
# each adjudicator, because those genuinely differ and pretending otherwise
# would be the opposite error.
#
# Bash 3.2. No associative arrays. Never `set -e`.

# shadow_band <k> <n> -> DENY | ADVISORY-ONLY | NARROWED | INSUFFICIENT
#
# Exact Clopper-Pearson, stated as a direct CDF comparison so no interval
# inversion is needed (the binomial CDF is monotone in p):
#   DENY          <=> P(X <= k | n, DENY_P)     <  ALPHA
#   ADVISORY-ONLY <=> P(X >= k | n, ADVISORY_P) <= ALPHA
# Do NOT substitute a normal approximation: Wilson is anti-conservative in the
# tail and calls 8/23 ADVISORY-ONLY where exact says NARROWED (a pinned test).
#
# The three probabilities are read from the CALLER's environment so each leg's
# pre-registration stays the authority for its own numbers; the defaults match
# both current pre-registrations and exist only so the function is usable
# stand-alone.
shadow_band() {
    awk -v k="${1:-0}" -v n="${2:-0}" -v a="${ALPHA:-0.05}" \
        -v dp="${DENY_P:-0.10}" -v ap="${ADVISORY_P:-0.20}" '
    function tail(kk, nn, p, mode,   i, t, s) {
        # mode "le": sum_{i<=kk}   mode "ge": sum_{i>=kk}
        # Term recurrence rather than factorials, so large n cannot overflow.
        s = 0; t = (1 - p) ^ nn
        for (i = 0; i <= nn; i++) {
            if (mode == "le" && i <= kk) s += t
            if (mode == "ge" && i >= kk) s += t
            if (i < nn) t = t * (nn - i) / (i + 1) * p / (1 - p)
        }
        return s
    }
    BEGIN {
        if (n < 1) { print "INSUFFICIENT"; exit }
        if (tail(k, n, dp, "le") <  a) { print "DENY";          exit }
        if (tail(k, n, ap, "ge") <= a) { print "ADVISORY-ONLY"; exit }
        print "NARROWED"
    }'
}

# SHADOW_AWK_EPOCH — shared awk prelude converting ISO-8601 UTC to epoch
# seconds, returning -1 when unparseable. In awk rather than `date` because
# `date -d` (GNU) and `date -j -f` (BSD/macOS) are mutually incompatible, and
# macOS awk has no mktime().
SHADOW_AWK_EPOCH='
    function days_from_civil(y, m, d,   era, yoe, doy, doe) {
        if (m <= 2) y = y - 1
        era = int((y >= 0 ? y : y - 399) / 400)
        yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
    function iso_epoch(s,   y, mo, d, hh, mi, ss) {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) return -1
        y  = substr(s,1,4)+0;  mo = substr(s,6,2)+0;  d  = substr(s,9,2)+0
        hh = substr(s,12,2)+0; mi = substr(s,15,2)+0; ss = substr(s,18,2)+0
        return days_from_civil(y, mo, d) * 86400 + hh * 3600 + mi * 60 + ss
    }'

# shadow_group_episodes <window_sec>
#   stdin : TSV  <repo> <branch> <session_token> <ts-iso8601> <record_id>
#   stdout: TSV  <episode_id> <repo> <branch> <session_token> <record_ids_csv>
#
# Membership: same (repo, branch, session_token) AND ts within <window_sec> of
# the episode's FIRST record — anchored, not rolling. A rolling gap would chain
# a whole day of intermittent pushes into one episode and drive the denominator
# below the real number of decision points.
#
# Field splitting is done ENTIRELY in awk. `IFS=$'\t' read` treats tab as IFS
# WHITESPACE, so consecutive tabs collapse and every field after an empty one
# shifts left — a record with an empty branch (which both writers emit whenever
# `git rev-parse --abbrev-ref HEAD` fails) silently vanished from the
# denominator with no exclusion row. awk with an explicit -F'\t' preserves
# empty fields.
shadow_group_episodes() {
    local _w="${1:-1800}"
    awk -F'\t' "${SHADOW_AWK_EPOCH}"'
        {
          # A malformed ts is EXCLUDED, not merged: iso_epoch returns -1 for
          # every unparseable value, so two corrupt records sharing a key would
          # satisfy (-1)-(-1)=0 <= window and collapse into one episode on a
          # time relation nothing verified. Excluding keeps corrupt data from
          # moving the denominator either way, and inflation is the dangerous
          # direction because it makes the floor easier to reach.
          if ($5 == "") next
          e = iso_epoch($4)
          if (e < 0) next
          print $1 "\t" $2 "\t" $3 "\t" e "\t" $5
        }' \
    | sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 -k4,4n \
    | awk -F'\t' -v w="${_w}" '
        # Compare the three key fields DIRECTLY rather than concatenating them
        # with a separator. A concatenated key collides whenever a field
        # contains the separator byte: branch="x\001y" + token="t1" builds the
        # same key as branch="x" + token="y\001t1", silently merging unrelated
        # episodes and shrinking the denominator. Field-wise comparison has no
        # such class of bug and is simpler.
        {
          if (NR == 1 || $1 != p1 || $2 != p2 || $3 != p3 || ($4 - anchor) > w) {
            if (NR > 1) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids
            eid = $5; erepo = $1; ebranch = $2; etok = $3; ids = $5
            anchor = $4; p1 = $1; p2 = $2; p3 = $3
          } else {
            ids = ids "," $5
          }
        }
        END { if (NR > 0) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids }'
}
