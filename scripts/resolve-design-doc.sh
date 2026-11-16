#!/bin/bash
# resolve-design-doc.sh — where is this change's design doc? Read-only.
#
# WHY THIS EXISTS: readers of a change's design doc (openspec-ship's Divergences step,
# deploy-gate's design-intent check) took its path from session state, which only a
# model-performed `persist-state.sh upsert-change` ever wrote. The one prompt that asked
# for that write was a phase hint (measured: run in 5 of 188 sessions that saw it), and
# the shipped phase hints are gone. So the readers found nothing and did nothing, without
# saying so. This script lets a reader look for the doc itself and SAY what it found.
#
# Usage:
#   resolve-design-doc.sh [--slug <change-slug>]
#
# Output, one tab-separated line on stdout:
#   <outcome>\t<source>\t<path>\t<count>
#     resolved   exactly one readable file          source: state | openspec | docs-plans
#     stale      state records a path, file unreadable   source: state
#     ambiguous  more than one candidate            source: state | docs-plans
#     absent     nothing recorded, nothing found    source: none
#   `ambiguous` is followed by one candidate path per line.
#
# Order: (1) the path recorded in session state for the slug, CHECKED for readability and
# reported `stale` when it fails (a record is never trusted blind and never silently
# replaced by a filename match; the one exception is the same basename under
# docs/plans/archive/, where openspec-ship's archive step moves it); (2) openspec/changes/<slug>/design.md;
# (3) docs/plans/YYYY-MM-DD-<slug>-design.md.
#
# Without --slug only arm (1) runs, over changes not yet marked archived. This script
# does NOT derive a slug from the branch name: a branch name is a candidate, not an
# identity, and a wrong guess attaches one feature's design to another's report.
#
# A path found by arms (2) or (3) is evidence, not identity. Callers must label it as
# found by filename, and must not move or archive a file on the strength of it.
#
# Exit: 0 decided (including `absent`); 2 usage; 3 cannot check (a state file exists and
# cannot be parsed, or jq is missing while one exists). Exit 3 prints no outcome line, so
# "could not check" can never be read as "absent".
#
# Writes nothing. Bash 3.2.
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

_usage() { echo "resolve-design-doc: usage: resolve-design-doc.sh [--slug <change-slug>]" >&2; }

SLUG=""
HAVE_SLUG=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --slug)
            [ "$#" -ge 2 ] || { _usage; exit 2; }
            SLUG="$2"; HAVE_SLUG=1; shift 2 ;;
        *) _usage; exit 2 ;;
    esac
done
if [ "${HAVE_SLUG}" -eq 1 ]; then
    # A slug names one path component. Empty, a path separator, a leading dot or a
    # control character cannot be one, and would break the output format or leave the
    # two directories this script reads.
    case "${SLUG}" in
        ''|*/*|.*|*"$(printf '\t')"*|*"
"*) echo "resolve-design-doc: not a change slug" >&2; _usage; exit 2 ;;
    esac
fi

ROOT="${SKILL_PROJECT_ROOT:-}"
[ -n "${ROOT}" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
[ -n "${ROOT}" ] || ROOT="$(pwd)"

# --- token: the openspec-state resolution, as scripts/persist-state.sh does it --------
# resolve_own_session_token, else the singleton; SKILL_SESSION_TOKEN deliberately not
# honored (no openspec-state writer or reader honors it, #157).
TOKEN=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=../hooks/lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_own_session_token >/dev/null 2>&1 && TOKEN="$(resolve_own_session_token 2>/dev/null)"
fi
[ -n "${TOKEN}" ] || TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)" || true

_emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
_readable() { # <recorded path> — relative paths are relative to the repo root
    case "$1" in
        /*) [ -f "$1" ] && [ -r "$1" ] ;;
        *)  [ -f "${ROOT}/$1" ] && [ -r "${ROOT}/$1" ] ;;
    esac
}

# --- arm 1: the recorded path ---------------------------------------------------------
RECORDED=""
if [ -n "${TOKEN}" ]; then
    STATE="${HOME}/.claude/.skill-openspec-state-${TOKEN}"
    if [ -f "${STATE}" ]; then
        command -v jq >/dev/null 2>&1 || { echo "resolve-design-doc: cannot check: jq not found and a state file exists" >&2; exit 3; }
        jq -e 'type == "object"' "${STATE}" >/dev/null 2>&1 || { echo "resolve-design-doc: cannot check: state file is not a JSON object" >&2; exit 3; }
        if [ "${HAVE_SLUG}" -eq 1 ]; then
            RECORDED="$(jq -r --arg s "${SLUG}" '(.changes // {})[$s].design_path // "" | if type == "string" then . else "" end' "${STATE}" 2>/dev/null)" \
                || { echo "resolve-design-doc: cannot check: state file could not be read" >&2; exit 3; }
        else
            _open="$(jq -r '[(.changes // {}) | to_entries[]
                    | select((.value.design_path | type) == "string" and .value.design_path != "")
                    | select(.value.archived_at == null)
                    | .value.design_path] | .[]' "${STATE}" 2>/dev/null)" \
                || { echo "resolve-design-doc: cannot check: state file could not be read" >&2; exit 3; }
            _n=0
            if [ -n "${_open}" ]; then
                while IFS= read -r _line; do _n=$((_n + 1)); done <<EOF
${_open}
EOF
            fi
            if [ "${_n}" -gt 1 ]; then
                _emit ambiguous state "" "${_n}"
                printf '%s\n' "${_open}"
                exit 0
            fi
            RECORDED="${_open}"
        fi
    fi
fi
# A recorded path holding a tab or newline cannot be reported in this format.
case "${RECORDED}" in
    *"$(printf '\t')"*|*"
"*) echo "resolve-design-doc: cannot check: the recorded path holds a control character" >&2; exit 3 ;;
esac
if [ -n "${RECORDED}" ]; then
    if _readable "${RECORDED}"; then
        _emit resolved state "${RECORDED}" 1
    elif [ -f "${ROOT}/docs/plans/archive/${RECORDED##*/}" ] && [ -r "${ROOT}/docs/plans/archive/${RECORDED##*/}" ]; then
        # openspec-ship Step 7b moves a recorded design doc to docs/plans/archive/ and
        # the Divergences step runs after it. Same basename, that one directory: this is
        # the recorded doc at its new path, not a filename guess.
        _emit resolved state "docs/plans/archive/${RECORDED##*/}" 1
    else
        _emit stale state "${RECORDED}" 0
    fi
    exit 0
fi

# Without a slug there is nothing to look for by name.
if [ "${HAVE_SLUG}" -eq 0 ]; then
    _emit absent none "" 0
    exit 0
fi

# --- arm 2: the committed OpenSpec change ---------------------------------------------
if [ -f "${ROOT}/openspec/changes/${SLUG}/design.md" ] && [ -r "${ROOT}/openspec/changes/${SLUG}/design.md" ]; then
    _emit resolved openspec "openspec/changes/${SLUG}/design.md" 1
    exit 0
fi

# --- arm 3: docs/plans/YYYY-MM-DD-<slug>-design.md ------------------------------------
# The slug is compared as a FIXED STRING against what sits between the date prefix and
# the suffix, so `auth` does not match `auth-tokens`, `tokens` does not match
# `auth-tokens`, and a slug holding glob or regex characters matches only itself.
_cands=""
_count=0
for _f in "${ROOT}/docs/plans/"*-design.md; do
    [ -f "${_f}" ] && [ -r "${_f}" ] || continue
    _b="${_f##*/}"
    case "${_b}" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*-design.md) ;;
        *) continue ;;
    esac
    _mid="${_b#???????????}"
    _mid="${_mid%-design.md}"
    [ "${_mid}" = "${SLUG}" ] || continue
    _count=$((_count + 1))
    if [ -z "${_cands}" ]; then _cands="docs/plans/${_b}"; else _cands="${_cands}
docs/plans/${_b}"; fi
done

if [ "${_count}" -eq 1 ]; then
    _emit resolved docs-plans "${_cands}" 1
elif [ "${_count}" -gt 1 ]; then
    _emit ambiguous docs-plans "" "${_count}"
    printf '%s\n' "${_cands}"
else
    _emit absent none "" 0
fi
exit 0
