#!/bin/bash
# shadow-adjudicate.sh — label IMPLEMENT-leg shadow records (the Stage C1 corpus)
# and report the pre-registered false-block rate over independent episodes.
#
# DIAGNOSTIC ONLY. Never sourced by hooks/openspec-guard.sh, deliberately
# EXCLUDED from _GATE_ENFORCE_LIBS, writes no gate state, and its output MUST
# NOT be wired into an enforcement decision — the guard is the only decider.
#
# The pre-registration in openspec/changes/implement-shadow-event/design.md is an
# INPUT here, not something this script may redefine: the bands, the n=29 floor,
# the >=2-repo diversity requirement and the episode denominator all come from
# that file.
#
# Bash 3.2. Never `set -e`. Never reads stdin.
set -u

REQUIRED_PREDICATE_VERSION=2
FLOOR_EPISODES=29
FLOOR_REPOS=2
EPISODE_WINDOW_SEC=1800
ALPHA=0.05
DENY_P=0.10
ADVISORY_P=0.20

SHADOW_LOG="${IMPLEMENT_SHADOW_LOG:-$HOME/.claude/.push-implement-shadow.jsonl}"
ADJ_LOG="${IMPLEMENT_ADJUDICATION_LOG:-$HOME/.claude/.push-implement-adjudication.jsonl}"

# _band <k> <n> -> DENY | ADVISORY-ONLY | NARROWED | INSUFFICIENT
#
# Exact Clopper-Pearson, stated as a direct CDF comparison so no interval
# inversion is needed (the binomial CDF is monotone in p):
#   DENY          <=> P(X <= k | n, 0.10) <  alpha
#   ADVISORY-ONLY <=> P(X >= k | n, 0.20) <= alpha
# Do NOT substitute a normal approximation: Wilson is anti-conservative in the
# tail and calls 8/23 ADVISORY-ONLY where exact says NARROWED (a pinned test).
_band() {
    awk -v k="${1:-0}" -v n="${2:-0}" -v a="${ALPHA}" \
        -v dp="${DENY_P}" -v ap="${ADVISORY_P}" '
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

# _iso_epoch <iso8601-utc> -> epoch seconds, or -1 if unparseable.
# Implemented in awk rather than via `date`, because `date -d` (GNU) and
# `date -j -f` (BSD/macOS) are mutually incompatible and this must run on both.
_iso_epoch() {
    awk -v s="${1:-}" '
    function days_from_civil(y, m, d,   era, yoe, doy, doe) {
        if (m <= 2) y = y - 1
        era = int((y >= 0 ? y : y - 399) / 400)
        yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
    BEGIN {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) { print -1; exit }
        y  = substr(s,1,4)+0;  mo = substr(s,6,2)+0;  d  = substr(s,9,2)+0
        hh = substr(s,12,2)+0; mi = substr(s,15,2)+0; ss = substr(s,18,2)+0
        print days_from_civil(y, mo, d) * 86400 + hh * 3600 + mi * 60 + ss
    }'
}

# _episodes — group v2 shadow records into independent episodes.
# One TAB-separated line per episode:
#   <episode_id> <repo> <branch> <session_token> <record_ids_csv>
# Membership: same (repo, branch, session_token) AND ts within
# EPISODE_WINDOW_SEC of the episode's FIRST record — anchored, not rolling.
# A rolling gap would chain a whole day of intermittent pushes into one episode
# and drive the denominator below the real number of decision points.
_episodes() {
    [ -f "${SHADOW_LOG}" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
        select(.predicate_version == $pv)
        | [.repo, .branch, .session_token, .ts, .record_id] | @tsv
      ' "${SHADOW_LOG}" 2>/dev/null \
    | while IFS="$(printf '\t')" read -r _repo _branch _tok _ts _rid; do
          [ -z "${_rid:-}" ] && continue
          printf '%s\t%s\t%s\t%s\t%s\n' "$_repo" "$_branch" "$_tok" "$(_iso_epoch "$_ts")" "$_rid"
      done \
    | sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 -k4,4n \
    | awk -F'\t' -v w="${EPISODE_WINDOW_SEC}" '
        {
          key = $1 "\001" $2 "\001" $3
          if (NR == 1 || key != prev_key || ($4 - anchor) > w) {
            if (NR > 1) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids
            eid = $5; erepo = $1; ebranch = $2; etok = $3; ids = $5
            anchor = $4; prev_key = key
          } else {
            ids = ids "," $5
          }
        }
        END { if (NR > 0) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids }'
}

# Allow tests to source the helpers without executing a command.
[ "${1:-}" = "--source-only" ] && return 0 2>/dev/null
