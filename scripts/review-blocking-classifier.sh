#!/bin/bash
# review-blocking-classifier.sh — did the automated review report blocking issues?
#
#   review-blocking-classifier.sh <review-body-file>
#
# Prints `blocking`, `none`, or `unknown`. Exit is always 0; the ANSWER is the
# output, because a non-zero exit here would be read as "the step failed".
#
# WHY THIS IS NOT ANCHORED ON A HEADING. The workflow prompt asks for
# "Section 3 — Blocking issues 🚫". Three real review bodies from one day
# rendered that same section three different ways:
#
#     ## Blocking issues 🚫       (PR #281)
#     ### Blocking issues 🚫      (PR #284)
#     **Blocking issues 🚫**      (PR #286)   <- not a heading at all
#
# A `^#+ Blocking issues` matcher — the obvious one — silently misses the third.
# That is this repo's recorded failure shape: a matcher whose unit is the line
# or the heading, over output whose unit is a section, reporting clean in the
# direction it cannot see. So the anchor is the PHRASE, and the section end is
# any of: a markdown heading, a bold-only line, a horizontal rule, or EOF.
#
# FAIL DIRECTION IS `unknown` -> the caller COMMENTS, it does not request
# changes. A false `blocking` submits a CHANGES_REQUESTED review that can block
# a human's merge and cannot be deleted, only dismissed. A missed `blocking`
# leaves exactly today's behaviour — the verdict layer stays dark for that PR.
# The gate never depends on this to CLEAR anything, so a miss loses information
# while a false positive costs someone else's merge. Asymmetric, so bias to
# silence.
set -u

BODY="${1:-}"
[ -n "${BODY}" ] || { echo unknown; exit 0; }
[ -r "${BODY}" ] || { echo unknown; exit 0; }

# Extract the blocking section: from the line naming it, to the next section
# boundary. `tolower` so heading case cannot matter.
_SECTION="$(awk '
    function is_boundary(l) {
        return (l ~ /^[[:space:]]*#+[[:space:]]/) \
            || (l ~ /^[[:space:]]*\*\*[^*]+\*\*[[:space:]]*$/) \
            || (l ~ /^[[:space:]]*-{3,}[[:space:]]*$/)
    }
    {
        low = tolower($0)
        if (!inside && low ~ /blocking issue/) { inside = 1; next }
        if (inside && is_boundary($0)) { exit }
        if (inside) print
    }
' "${BODY}")"

# No section at all: the review did not follow the contract. Not "none".
if ! printf '%s' "${_SECTION}" | grep -q '[^[:space:]]'; then
    # The phrase may be absent entirely, or present with an empty body.
    if grep -qi 'blocking issue' "${BODY}"; then
        echo unknown
    else
        echo unknown
    fi
    exit 0
fi

# A "none" section is a short statement of absence and nothing else. Observed
# forms: "None.", "None found.". Anything with a list item, a file:line, or more
# than a couple of lines of prose is treated as content.
_STRIPPED="$(printf '%s' "${_SECTION}" | tr -d '[:space:]')"
_LOWER="$(printf '%s' "${_STRIPPED}" | tr '[:upper:]' '[:lower:]')"

case "${_LOWER}" in
    none|none.|nonefound|nonefound.|nonefound\!|n/a|n/a.|nothingblocking|nothingblocking.)
        echo none; exit 0 ;;
esac

# A list item or a file:line reference in the section means findings.
if printf '%s' "${_SECTION}" | grep -qE '^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]'; then
    echo blocking; exit 0
fi
if printf '%s' "${_SECTION}" | grep -qE '[A-Za-z0-9_./-]+\.(sh|py|json|ya?ml|md):[0-9]+'; then
    echo blocking; exit 0
fi

# Prose that merely says there is nothing, in a form not enumerated above — the
# "None that block merge, but…" case. We cannot tell; say so.
echo unknown
exit 0
