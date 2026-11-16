#!/usr/bin/env bash
# test-resolve-design-doc.sh — scripts/resolve-design-doc.sh answers "where is this
# change's design doc" WITHOUT a model-performed state write, read-only, with four
# outcomes. Design: openspec/changes/design-doc-resolution/.
#
# Why it exists: the PERSIST DESIGN phase hint was the only text that asked the model to
# record a design doc's path (measured: 5 of 188 sessions that saw it ran it), and the
# shipped phase hints were removed (openspec/changes/archive/2026-11-16-registered-hint-cut).
# Readers of that recorded path found nothing and did nothing, silently.
#
# Output contract, one tab-separated line: <outcome> <source> <path> <count>
#   outcome: resolved | stale | ambiguous | absent     source: state | openspec | docs-plans | none
#   `ambiguous` is followed by one candidate per line. Exit 0 decided, 2 usage, 3 cannot check.
#
# What these cells do NOT show: that a doc found by filename is the RIGHT doc. Exactly one
# date-prefixed filename match is evidence, not identity; the callers label it as such.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-resolve-design-doc.sh ==="

SCRIPT="${PROJECT_ROOT}/scripts/resolve-design-doc.sh"
assert_file_exists "resolve-design-doc.sh exists" "${SCRIPT}"

TAB="$(printf '\t')"
_OLDHOME="$HOME"
WORK="$(mktemp -d /tmp/rdd-XXXXXX)"
export HOME="${WORK}/home"; mkdir -p "$HOME/.claude"
T="session-rdd"
printf '%s' "${T}" > "$HOME/.claude/.skill-session-token"
STATE="$HOME/.claude/.skill-openspec-state-${T}"

# _repo <name> — a fresh throwaway repo root (a plain directory: the script is handed
# its root through SKILL_PROJECT_ROOT, so no git is needed and none is run).
_repo() { REPO="${WORK}/$1"; rm -rf "${REPO}"; mkdir -p "${REPO}/docs/plans" "${REPO}/openspec/changes"; }
_run() {
    ( cd "${REPO}" && env -u CLAUDE_CODE_SESSION_ID SKILL_PROJECT_ROOT="${REPO}" \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" "$@" 2>"${WORK}/stderr" )
}
# _snap — everything the script could have written: the state file and the repo tree.
_snap() { { cksum "${STATE}" 2>/dev/null; ( cd "${REPO}" && find . -type f -exec cksum {} + | LC_ALL=C sort ); ls "$HOME/.claude"; } 2>/dev/null; }
# _cell <label> <expected first line> [args...] — runs, compares line 1, and requires
# exit 0, empty stderr and an untouched state file and repo tree.
_cell() {
    local label="$1" want="$2"; shift 2
    local before after out rc
    before="$(_snap)"
    out="$(_run "$@")"; rc=$?
    after="$(_snap)"
    assert_equals "${label}" "${want}" "$(printf '%s\n' "${out}" | head -1)"
    assert_equals "${label}: exit 0" "0" "${rc}"
    assert_equals "${label}: stderr empty" "" "$(cat "${WORK}/stderr")"
    assert_equals "${label}: wrote nothing" "${before}" "${after}"
    LAST_OUT="${out}"
}
_state_one() { # <slug> <design_path> [archived_at]
    jq -n --arg s "$1" --arg d "$2" --arg a "${3:-}" \
        '{changes: {($s): {design_path: $d, archived_at: (if $a == "" then null else $a end)}}}' > "${STATE}"
}

# --- absent -------------------------------------------------------------------
_repo r-absent; rm -f "${STATE}"
_cell "no state, no files" "absent${TAB}none${TAB}${TAB}0" --slug f

# --- state arm ----------------------------------------------------------------
_repo r-state; : > "${REPO}/docs/plans/2026-01-01-f-design.md"
_state_one f "docs/plans/2026-01-01-f-design.md"
_cell "recorded relative path, readable" "resolved${TAB}state${TAB}docs/plans/2026-01-01-f-design.md${TAB}1" --slug f

_repo r-state-abs; : > "${REPO}/elsewhere.md"
_state_one f "${REPO}/elsewhere.md"
_cell "recorded absolute path, readable" "resolved${TAB}state${TAB}${REPO}/elsewhere.md${TAB}1" --slug f

# A recorded path is checked, never trusted, and never silently replaced by a filename
# match: the reader has to hear that its record is stale.
_repo r-stale; : > "${REPO}/docs/plans/2026-01-01-f-design.md"
_state_one f "docs/plans/2025-12-31-f-design.md"
_cell "recorded path missing, a filename match exists" "stale${TAB}state${TAB}docs/plans/2025-12-31-f-design.md${TAB}0" --slug f

# With --slug the change may already be marked archived (openspec-ship marks it before
# its Divergences step), so archived_at must not hide the record.
_repo r-archived; : > "${REPO}/docs/plans/2026-01-01-f-design.md"
_state_one f "docs/plans/2026-01-01-f-design.md" "2026-01-02T00:00:00Z"
_cell "--slug reads an archived change's record" "resolved${TAB}state${TAB}docs/plans/2026-01-01-f-design.md${TAB}1" --slug f

# --- filename arms ------------------------------------------------------------
_repo r-openspec; rm -f "${STATE}"; mkdir -p "${REPO}/openspec/changes/f"; : > "${REPO}/openspec/changes/f/design.md"
_cell "openspec change folder" "resolved${TAB}openspec${TAB}openspec/changes/f/design.md${TAB}1" --slug f

_repo r-docs; : > "${REPO}/docs/plans/2026-01-01-f-design.md"
_cell "one docs/plans match" "resolved${TAB}docs-plans${TAB}docs/plans/2026-01-01-f-design.md${TAB}1" --slug f

_repo r-order; mkdir -p "${REPO}/openspec/changes/f"; : > "${REPO}/openspec/changes/f/design.md"; : > "${REPO}/docs/plans/2026-01-01-f-design.md"
_cell "openspec wins over docs/plans" "resolved${TAB}openspec${TAB}openspec/changes/f/design.md${TAB}1" --slug f

_repo r-two; : > "${REPO}/docs/plans/2026-01-01-f-design.md"; : > "${REPO}/docs/plans/2026-02-01-f-design.md"
_cell "two docs/plans matches" "ambiguous${TAB}docs-plans${TAB}${TAB}2" --slug f
assert_equals "ambiguous lists both candidates, sorted" \
    "docs/plans/2026-01-01-f-design.md docs/plans/2026-02-01-f-design.md" \
    "$(printf '%s\n' "${LAST_OUT}" | sed 1d | tr '\n' ' ' | sed 's/ $//')"

# --- a slug is a fixed string, anchored after the date prefix -----------------
_repo r-prefix; : > "${REPO}/docs/plans/2026-01-01-auth-design.md"; : > "${REPO}/docs/plans/2026-01-01-auth-tokens-design.md"
_cell "prefix slug matches only itself" "resolved${TAB}docs-plans${TAB}docs/plans/2026-01-01-auth-design.md${TAB}1" --slug auth
_cell "longer slug matches only itself" "resolved${TAB}docs-plans${TAB}docs/plans/2026-01-01-auth-tokens-design.md${TAB}1" --slug auth-tokens
_cell "a suffix of another slug is not a match" "absent${TAB}none${TAB}${TAB}0" --slug tokens

_repo r-meta; : > "${REPO}/docs/plans/2026-01-01-axb-design.md"; mkdir -p "${REPO}/openspec/changes/axb"; : > "${REPO}/openspec/changes/axb/design.md"
for _s in 'a.b' 'a*b' 'a[b]' 'a?b'; do
    _cell "metacharacter slug ${_s} is literal" "absent${TAB}none${TAB}${TAB}0" --slug "${_s}"
done
# Positive control for the loop above: the decoy IS findable under its own name, so
# "absent" there was the slug being literal, not the fixture being unreadable.
_cell "control: the decoy resolves under its own slug" "resolved${TAB}openspec${TAB}openspec/changes/axb/design.md${TAB}1" --slug axb

# A slug that could leave the two directories is refused as usage, not resolved.
_repo r-traverse; : > "${REPO}/design.md"
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" --slug '../..' >/dev/null 2>&1 )
assert_equals "a slug containing a slash exits 2" "2" "$?"

# --- no --slug: only the recorded arm, and only OPEN changes ------------------
_repo r-noslug; : > "${REPO}/docs/plans/2026-01-01-f-design.md"
_state_one f "docs/plans/2026-01-01-f-design.md"
_cell "no slug, one open recorded change" "resolved${TAB}state${TAB}docs/plans/2026-01-01-f-design.md${TAB}1"

jq -n '{changes: {f: {design_path: "docs/plans/2026-01-01-f-design.md", archived_at: null}, g: {design_path: "docs/plans/2026-01-01-g-design.md", archived_at: null}}}' > "${STATE}"
_cell "no slug, two open recorded changes" "ambiguous${TAB}state${TAB}${TAB}2"

_state_one f "docs/plans/2026-01-01-f-design.md" "2026-01-02T00:00:00Z"
_cell "no slug, the only recorded change is archived" "absent${TAB}none${TAB}${TAB}0"

rm -f "${STATE}"
_cell "no slug, no state: filenames are not searched" "absent${TAB}none${TAB}${TAB}0"

# --- another session's state is never read ------------------------------------
_repo r-foreign; : > "${REPO}/docs/plans/2026-01-01-f-design.md"
jq -n '{changes: {f: {design_path: "docs/plans/2026-01-01-f-design.md", archived_at: null}}}' > "$HOME/.claude/.skill-openspec-state-session-someone-else"
rm -f "${STATE}"
_cell "a foreign token's state file is not read" "absent${TAB}none${TAB}${TAB}0"
rm -f "$HOME/.claude/.skill-openspec-state-session-someone-else"

# --- cannot check -------------------------------------------------------------
# jq is hidden by a PATH holding ONLY the tools the script may need. The precondition is
# asserted at run time, in the same environment the script gets: macOS ships /usr/bin/jq,
# so a PATH of system dirs would NOT hide it and this cell would pass having tested nothing.
_NOJQ="${WORK}/nojq-bin"; mkdir -p "${_NOJQ}"
for _t in cat dirname basename ls env sort head sed tr; do
    _p="$(command -v "${_t}" 2>/dev/null)"; [ -n "${_p}" ] && ln -sf "${_p}" "${_NOJQ}/${_t}"
done
_repo r-nojq; _state_one f "docs/plans/2026-01-01-f-design.md"
if PATH="${_NOJQ}" /bin/bash -c 'command -v jq' >/dev/null 2>&1; then
    _record_fail "precondition: jq is not reachable on the restricted PATH" "jq is still found; the exit-3 cell would test nothing"
else
    _record_pass "precondition: jq is not reachable on the restricted PATH"
    ( cd "${REPO}" && PATH="${_NOJQ}" HOME="$HOME" SKILL_PROJECT_ROOT="${REPO}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" --slug f >"${WORK}/nojq.out" 2>/dev/null )
    assert_equals "a state file that cannot be parsed for want of jq exits 3" "3" "$?"
    assert_equals "exit 3 prints no outcome line" "" "$(cat "${WORK}/nojq.out")"
fi

# A state file that exists and is not JSON is "cannot check", never "absent".
_repo r-corrupt; printf 'not json' > "${STATE}"
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" --slug f >"${WORK}/corrupt.out" 2>/dev/null )
assert_equals "an unparseable state file exits 3" "3" "$?"
assert_equals "an unparseable state file prints no outcome line" "" "$(cat "${WORK}/corrupt.out")"
# Valid JSON of the wrong shape is the same case: jq would read `.changes` off an array
# as an error or off a string as null, and null must not become "absent".
for _shape in '[]' '"x"' 'null'; do
    printf '%s' "${_shape}" > "${STATE}"
    ( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" --slug f >"${WORK}/shape.out" 2>/dev/null )
    assert_equals "a state file holding ${_shape} exits 3" "3" "$?"
    assert_equals "a state file holding ${_shape} prints no outcome line" "" "$(cat "${WORK}/shape.out")"
done
rm -f "${STATE}"

# --- usage --------------------------------------------------------------------
_repo r-usage
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${SCRIPT}" --bogus >/dev/null 2>&1 ); assert_equals "unknown flag exits 2" "2" "$?"
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${SCRIPT}" --slug >/dev/null 2>&1 );  assert_equals "--slug without a value exits 2" "2" "$?"
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${SCRIPT}" --slug '' >/dev/null 2>&1 ); assert_equals "an empty slug exits 2" "2" "$?"

export HOME="${_OLDHOME}"
rm -rf "${WORK}"
print_summary
exit $?
