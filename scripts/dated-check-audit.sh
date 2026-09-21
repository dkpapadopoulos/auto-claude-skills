#!/usr/bin/env bash
# dated-check-audit.sh — do `dated-check` issues' body `due:` lines still agree
# with the latest deferral recorded on them? (#266)
#
# WHY. When a dated commitment is extended, the new date tends to land in a
# COMMENT while the body's `due:` line — the field the label query reads — keeps
# the superseded date. The queryable surface and the real commitment drift, and
# the overdue figure the query reports becomes wrong. A wrong number is worse
# than no number, because it is quotable.
#
# WHAT THIS IS NOT. #182 pre-registered whether lapsed dated commitments are a
# VISIBILITY problem and resolved that they are a PRIORITIZATION problem, ruling
# out digests and monitors. This adds none: no schedule, no notification, no
# workflow. It is run by a person who wants to know whether the field they are
# about to quote is current. If it ever grows a scheduled caller, that is
# grounds to delete it rather than trim it.
#
# THREE OUTCOMES, NEVER TWO.
#   0  clean       every issue's body `due:` is the latest date on the issue
#   1  divergent   at least one disagrees (each pair printed)
#   3  cannot-check something stopped it from knowing: no gh, no jq, an API
#                  error, or an issue with no parseable `due:` line
#
# The third exists because "checked and clean" and "could not check" are
# different states and only one of them licenses quoting the number. An audit
# that reports clean when it could not look is the defect it audits for.
set -u

LABEL="${DATED_CHECK_LABEL:-dated-check}"
FIXTURE_DIR="${DATED_CHECK_FIXTURES:-}"

_die_cannot_check() { printf 'cannot-check: %s\n' "$1" >&2; exit 3; }

# latest_commitment_in <text> — the newest ISO date stated as a COMMITMENT.
#
# NOT "the newest date appearing anywhere", which is what #266 proposed and what
# the first cut of this script implemented. Measured against the only live case
# it produced a FALSE POSITIVE: #124's body correctly reads `due: 2026-08-01`,
# and the newest date on the issue is `2026-09-19` — the day a comment was
# written, in the prose "Extended window executed 2026-09-19". Nothing was
# deferred to it. An audit whose whole purpose is that a wrong number is worse
# than no number must not invent one.
#
# So a date counts only where the surrounding words make it a commitment:
# due / deadline / extend / defer / revisit / re-evaluate / re-estimate, or a
# bare `until`/`by`. The context window is one line, which is where this
# language lives in practice.
#
# CEILING, stated: a deferral phrased without any of these words is missed, and
# the audit then reports clean. That is the same failure direction as having no
# audit at all, and the opposite of the false-positive direction, which would
# manufacture the wrong number this exists to prevent.
latest_commitment_in() {
    # TWO conditions, because either alone is wrong. The line must carry
    # commitment LANGUAGE, and the date must be TARGETED by it — a commitment
    # points AT a date. "Extended window executed 2026-09-19" satisfies the
    # first and not the second: it reports when something happened, it does not
    # move a deadline. That sentence is live on #124 and is why the first two
    # cuts of this function both reported a false divergence.
    printf '%s' "$1" \
        | grep -iE '(due|deadline|extend(ed|s)?|defer(red)?|revisit|re-?evaluat(e|ed|ion)|re-?estimate|new (date|window)|until|paused|postponed|on hold|blocked)' \
        | grep -oiE '(to|until|on|on/after|after|by|:)[[:space:]*_`"'"'"']{0,4}[0-9]{4}-[0-9]{2}-[0-9]{2}' \
        | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
        | sort | tail -1
}

# body_due <body> — the date on the body's `due:` line. Empty when absent.
body_due() {
    printf '%s' "$1" | grep -iE '^[[:space:]]*due:' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1
}

# audit_one <id> <body> <comments> -> prints a row, returns 0 clean / 1 divergent / 3 unparseable
audit_one() {
    local _id="$1" _body="$2" _comments="$3" _due _latest
    _due="$(body_due "${_body}")"
    if [ -z "${_due}" ]; then
        printf '%s\tcannot-check\tno parseable due: line\n' "${_id}"
        return 3
    fi
    # The latest date COMMITTED TO anywhere on the issue, body included: a
    # deferral recorded only in the body is still the record.
    _latest="$(latest_commitment_in "${_body}
${_comments}")"
    [ -n "${_latest}" ] || _latest="${_due}"
    if [ "${_due}" = "${_latest}" ]; then
        printf '%s\tclean\tdue=%s\n' "${_id}" "${_due}"
        return 0
    fi
    printf '%s\tdivergent\tbody-due=%s latest-stated=%s\n' "${_id}" "${_due}" "${_latest}"
    return 1
}

# --- fixture mode: audit a directory of <id>.body / <id>.comments pairs -------
# Exists so a run over a CLEAN live set still proves the audit can see a
# divergence. #266's own premise was stale by the time it was implemented — the
# single live divergence had been repaired hours after filing — so a live `0`
# on its own would have demonstrated nothing about whether this script works.
if [ -n "${FIXTURE_DIR}" ]; then
    [ -d "${FIXTURE_DIR}" ] || _die_cannot_check "fixture dir not found: ${FIXTURE_DIR}"
    _rc=0; _seen=0
    for _b in "${FIXTURE_DIR}"/*.body; do
        [ -e "${_b}" ] || continue
        _seen=$(( _seen + 1 ))
        _id="$(basename "${_b}" .body)"
        _c=""; [ -f "${FIXTURE_DIR}/${_id}.comments" ] && _c="$(cat "${FIXTURE_DIR}/${_id}.comments")"
        audit_one "${_id}" "$(cat "${_b}")" "${_c}"
        case "$?" in
            1) [ "${_rc}" -eq 3 ] || _rc=1 ;;
            3) _rc=3 ;;
        esac
    done
    [ "${_seen}" -gt 0 ] || _die_cannot_check "no .body fixtures in ${FIXTURE_DIR}"
    exit "${_rc}"
fi

# --- live mode ---------------------------------------------------------------
command -v gh >/dev/null 2>&1 || _die_cannot_check "gh not on PATH"
command -v jq >/dev/null 2>&1 || _die_cannot_check "jq not on PATH"

_json="$(gh issue list --label "${LABEL}" --state open --json number,body,comments 2>/dev/null)" \
    || _die_cannot_check "gh issue list failed for label ${LABEL}"
printf '%s' "${_json}" | jq -e . >/dev/null 2>&1 || _die_cannot_check "gh returned unparseable JSON"

_n="$(printf '%s' "${_json}" | jq 'length')"
if [ "${_n}" -eq 0 ]; then
    echo "no open issues labelled ${LABEL}"
    exit 0
fi

_rc=0
_i=0
while [ "${_i}" -lt "${_n}" ]; do
    _id="$(printf '%s' "${_json}" | jq -r ".[${_i}].number")"
    _body="$(printf '%s' "${_json}" | jq -r ".[${_i}].body // \"\"")"
    _comments="$(printf '%s' "${_json}" | jq -r ".[${_i}].comments[]?.body // \"\"")"
    audit_one "#${_id}" "${_body}" "${_comments}"
    case "$?" in
        1) [ "${_rc}" -eq 3 ] || _rc=1 ;;
        3) _rc=3 ;;
    esac
    _i=$(( _i + 1 ))
done
exit "${_rc}"
