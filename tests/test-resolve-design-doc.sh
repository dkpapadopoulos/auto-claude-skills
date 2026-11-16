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
# WORK is a mktemp path and never names HOME (the trap must not: tests restore HOME
# before exit, and a trap naming it would then remove the real one).
trap 'rm -rf "${WORK}"' EXIT
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

# A same-named file somewhere else is NOT the recorded doc, and that includes
# docs/plans/archive/, where openspec-ship moves recorded docs. An earlier cut accepted
# that directory; review measured it resolving a recorded openspec/changes/f/design.md
# and a recorded path outside the repo to an unrelated docs/plans/archive/design.md,
# with nothing in the output to tell the caller. The caller resolves BEFORE it moves
# anything and maps the path itself.
for _rec in "docs/plans/2026-01-01-f-design.md" "openspec/changes/f/design.md" "/nowhere/else/2026-01-01-f-design.md"; do
    _repo r-moved; mkdir -p "${REPO}/docs/plans/archive" "${REPO}/docs/old"
    : > "${REPO}/docs/plans/archive/${_rec##*/}"; : > "${REPO}/docs/old/${_rec##*/}"
    _state_one f "${_rec}"
    _cell "a same-named file in docs/plans/archive does not stand in for recorded ${_rec}" "stale${TAB}state${TAB}${_rec}${TAB}0" --slug f
done
# A recorded path that names a directory is not a readable doc.
_repo r-dir; mkdir -p "${REPO}/docs/plans/2026-01-01-f-design.md"
_state_one f "docs/plans/2026-01-01-f-design.md"
_cell "a recorded path that is a directory is stale" "stale${TAB}state${TAB}docs/plans/2026-01-01-f-design.md${TAB}0" --slug f
# docs/plans absent altogether, and a directory named like a design file, are both "absent".
_repo r-noplans; rm -rf "${REPO}/docs" ; rm -f "${STATE}"
_cell "no docs/plans directory at all" "absent${TAB}none${TAB}${TAB}0" --slug f
_repo r-dirnamed; mkdir -p "${REPO}/docs/plans/2026-01-01-f-design.md"
_cell "a directory named like a design file is not a candidate" "absent${TAB}none${TAB}${TAB}0" --slug f

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
    ( cd "${REPO}" && PATH="${_NOJQ}" HOME="$HOME" SKILL_PROJECT_ROOT="${REPO}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" --slug f >"${WORK}/nojq.out" 2>"${WORK}/nojq.err" )
    assert_equals "a state file that cannot be parsed for want of jq exits 3" "3" "$?"
    assert_equals "exit 3 prints no outcome line" "" "$(cat "${WORK}/nojq.out")"
    # The message tells the jq guard from the shape guard; without it, deleting the jq
    # guard still exits 3 (the shape guard then fails for want of jq) and nothing notices.
    assert_contains "the missing-jq case names jq" "jq not found" "$(cat "${WORK}/nojq.err")"
fi

# A state file that exists and is not JSON is "cannot check", never "absent".
_repo r-corrupt; printf 'not json' > "${STATE}"
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" --slug f >"${WORK}/corrupt.out" 2>/dev/null )
assert_equals "an unparseable state file exits 3" "3" "$?"
assert_equals "an unparseable state file prints no outcome line" "" "$(cat "${WORK}/corrupt.out")"
# Valid JSON of the wrong shape is the same case: jq would read `.changes` off an array
# as an error or off a string as null, and null must not become "absent".
# Each shape is tried with AND without --slug: review measured `{"changes":[]}` exiting 3
# with a slug and printing `absent` without one, and a numeric design_path falling
# through to a filename match that the caller would then describe as "nothing recorded".
# A decoy that matches by filename is present, so falling through would show as `resolved`.
: > "${REPO}/docs/plans/2026-01-01-f-design.md"
_before_shapes="$( ( cd "${REPO}" && find . -type f -exec cksum {} + | LC_ALL=C sort ) )"
_TABPATH="$(printf 'docs/plans/a\tb.md')"
_NLPATH="$(printf 'docs/plans/a\nb.md')"
while IFS= read -r _shape; do
    [ -n "${_shape}" ] || continue
    printf '%s' "${_shape}" > "${STATE}"
    for _args in "--slug f" ""; do
        # shellcheck disable=SC2086
        ( cd "${REPO}" && env -u CLAUDE_CODE_SESSION_ID SKILL_PROJECT_ROOT="${REPO}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${SCRIPT}" ${_args} >"${WORK}/shape.out" 2>"${WORK}/shape.err" )
        assert_equals "state ${_shape} [${_args:-no slug}] exits 3" "3" "$?"
        assert_equals "state ${_shape} [${_args:-no slug}] prints no outcome line" "" "$(cat "${WORK}/shape.out")"
        assert_contains "state ${_shape} [${_args:-no slug}] says it could not check" "cannot check" "$(cat "${WORK}/shape.err")"
    done
done <<SHAPES
[]
"x"
null
{"changes":[]}
{"changes":"x"}
{"changes":{"f":5}}
{"changes":{"f":{"design_path":5}}}
{"changes":{"f":{"design_path":false}}}
{"changes":{"f":{"design_path":["docs/plans/2026-01-01-f-design.md"]}}}
{"changes":{}}{"changes":{}}
$(jq -cn --arg p "${_TABPATH}" '{changes:{f:{design_path:$p}}}')
$(jq -cn --arg p "${_NLPATH}" '{changes:{f:{design_path:$p}}}')
SHAPES
assert_equals "the cannot-check cells wrote nothing in the repo" "${_before_shapes}" \
    "$( ( cd "${REPO}" && find . -type f -exec cksum {} + | LC_ALL=C sort ) )"
# Controls, so the loop above is not "everything exits 3": a well-formed empty state and
# a null design_path are decided, not refused, and DO fall through to the filename match.
printf '%s' '{"changes":{}}' > "${STATE}"
_cell "control: an empty changes object is decided" "resolved${TAB}docs-plans${TAB}docs/plans/2026-01-01-f-design.md${TAB}1" --slug f
printf '%s' '{"changes":{"f":{"design_path":null}}}' > "${STATE}"
_cell "control: a null design_path means nothing recorded" "resolved${TAB}docs-plans${TAB}docs/plans/2026-01-01-f-design.md${TAB}1" --slug f
rm -f "${STATE}"

# --- usage --------------------------------------------------------------------
_repo r-usage
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${SCRIPT}" --bogus >/dev/null 2>&1 ); assert_equals "unknown flag exits 2" "2" "$?"
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${SCRIPT}" --slug >/dev/null 2>&1 );  assert_equals "--slug without a value exits 2" "2" "$?"
( cd "${REPO}" && SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${SCRIPT}" --slug '' >/dev/null 2>&1 ); assert_equals "an empty slug exits 2" "2" "$?"

# --- the two skills call it, and say what each outcome means ------------------
# Content cells: they show the instruction is THERE, in the step that needs it. They do
# not show a model follows it.
_section() { # <file> <heading line> — the text from that heading up to the next heading of the same or higher level
    awk -v h="$2" '
        $0 == h { f = 1; lvl = match($0, /[^#]/) - 1; next }
        f && /^#+ / { n = match($0, /[^#]/) - 1; if (n <= lvl) f = 0 }
        f' "$1" 2>/dev/null
}
SHIP="${PROJECT_ROOT}/skills/openspec-ship/SKILL.md"
GATE="${PROJECT_ROOT}/skills/deploy-gate/SKILL.md"
_s3="$(_section "${SHIP}" '### Step 3: Create OR Sync Change Folder')"
_7c="$(_section "${SHIP}" '### Step 7c: Generate Divergences Report')"
_7b="$(_section "${SHIP}" '### Step 7b: Archive Intent Artifacts')"
_g4="$(awk '/^4\. \*\*Design Intent Exists\*\*/{f=1} f && /^### /{f=0} f' "${GATE}" 2>/dev/null)"
for _pair in "openspec-ship Step 3|${_s3}" "openspec-ship Step 7c|${_7c}" "openspec-ship Step 7b|${_7b}" "deploy-gate check 4|${_g4}"; do
    if [ -z "${_pair#*|}" ]; then
        _record_fail "${_pair%%|*}: section readable" "empty; every cell on it would pass or fail for the wrong reason"
    else
        _record_pass "${_pair%%|*}: section readable"
    fi
done
_CALL="'<PLUGIN_ROOT>/scripts/resolve-design-doc.sh' --slug"
# openspec-ship resolves in Step 3 and USES the answer in Step 7c. Order is the point:
# Step 3 can create openspec/changes/<f>/design.md, Step 6 moves that folder to the
# archive and Step 7b moves recorded docs, so a call at 7c reports a doc that was there a
# moment ago as absent or stale (measured in review: every spec-driven ship was told
# "No design doc found"), or finds the as-built design.md this session just wrote.
assert_contains "Step 3: calls the resolver by its plugin path, with the slug" "${_CALL}" "${_s3}"
assert_contains "Step 3: says it runs before anything is created or moved" "before anything is created or moved" "${_s3}"
assert_contains "Step 3: keeps the output for Step 7c" "keep its output for Step 7c" "${_s3}"
assert_equals "openspec-ship calls the resolver exactly once" "1" "$(grep -cF "resolve-design-doc.sh" "${SHIP}")"
_call_ln="$(grep -nF "resolve-design-doc.sh" "${SHIP}" | head -1 | cut -d: -f1)"
_pre_ln="$(grep -n '^\*\*Pre-flight check:\*\*' "${SHIP}" | head -1 | cut -d: -f1)"
_s6_ln="$(grep -n '^### Step 6: Archive & Cleanup' "${SHIP}" | head -1 | cut -d: -f1)"
case "${_call_ln}:${_pre_ln}:${_s6_ln}" in
    *[!0-9:]*|:*|*::*|*:) _record_fail "the resolver call precedes the pre-flight check and Step 6" "could not locate all three lines (${_call_ln}:${_pre_ln}:${_s6_ln})" ;;
    *)
        if [ "${_call_ln}" -lt "${_pre_ln}" ] && [ "${_pre_ln}" -lt "${_s6_ln}" ]; then
            _record_pass "the resolver call (line ${_call_ln}) precedes the pre-flight check (${_pre_ln}) and Step 6 (${_s6_ln})"
        else
            _record_fail "the resolver call precedes the pre-flight check and Step 6" "call at ${_call_ln}, pre-flight at ${_pre_ln}, Step 6 at ${_s6_ln}"
        fi ;;
esac
assert_contains "Step 7c: uses the outcome Step 3 kept" "the outcome Step 3 kept" "${_7c}"
assert_contains "deploy-gate check 4: calls the resolver by its plugin path, with the slug" "${_CALL}" "${_g4}"
assert_contains "deploy-gate check 4: no slug from the branch name" "do not make one up from the branch name" "${_g4}"
assert_contains "deploy-gate check 4: absent without a slug is only 'nothing recorded'" "means only that nothing was recorded" "${_g4}"
# A refused slug (exit 2) prints no outcome line either; unnamed, it reads as a pass or
# as exit 3. And the Output example must show what check 4 now produces: an outcome and
# its source, not the "<path> exists" evidence of the file test it replaced.
assert_contains "deploy-gate check 4: a refused slug is its own case" "exit 2" "${_g4}"
_g4_row="$(grep -F '| 4 | Design intent |' "${GATE}" 2>/dev/null)"
assert_equals "deploy-gate Output: exactly one example row for check 4" "1" "$(printf '%s\n' "${_g4_row}" | grep -c .)"
assert_contains "deploy-gate Output: the check 4 row shows an outcome and its source" "\`resolved\` (docs-plans)" "${_g4_row}"
assert_not_contains "deploy-gate Output: the check 4 row is not a file-exists test" "exists" "${_g4_row}"
for _pair in "openspec-ship Step 7c|${_7c}" "deploy-gate check 4|${_g4}"; do
    _l="${_pair%%|*}"; _t="${_pair#*|}"
    for _o in resolved stale ambiguous absent; do
        assert_contains "${_l}: names the outcome ${_o}" "\`${_o}\`" "${_t}"
    done
    assert_contains "${_l}: could-not-check is its own case" "exit 3" "${_t}"
    assert_not_contains "${_l}: no hook-style placeholder" "{{PLUGIN_ROOT}}" "${_t}"
done
# What to do per outcome lives in a reference file the step tells the reader to open:
# openspec-ship's SKILL.md sits within 100 bytes of its 19,500-byte re-attach budget
# (tests/test-skill-reattach-budget.sh), and Step 7c is near its end.
_REF_NAME="references/design-doc-outcomes.md"
_ref="$(cat "${PROJECT_ROOT}/skills/openspec-ship/${_REF_NAME}" 2>/dev/null)"
assert_contains "Step 7c: names the outcomes reference" "\`${_REF_NAME}\`" "${_7c}"
assert_contains "Step 7c: is never skipped silently" "Never skip this step silently" "${_7c}"
if [ -z "${_ref}" ]; then
    _record_fail "outcomes reference readable" "skills/openspec-ship/${_REF_NAME} is missing or empty; Step 7c points at nothing"
else
    _record_pass "outcomes reference readable"
fi
for _o in resolved stale ambiguous absent; do
    assert_contains "outcomes reference: has a row for ${_o}" "| \`${_o}\`" "${_ref}"
done
assert_contains "outcomes reference: could-not-check is its own row" "| exit 3" "${_ref}"
assert_contains "outcomes reference: the script is not run again at 7c" "Do not run it again here" "${_ref}"
assert_contains "outcomes reference: a filename match is labelled" "found by filename, not recorded" "${_ref}"
assert_contains "outcomes reference: a change-folder doc is labelled" "found in the change folder, not recorded in session state" "${_ref}"
assert_contains "outcomes reference: absent is said, not skipped" "No design doc found" "${_ref}"
assert_contains "outcomes reference: missing scenarios are said" "no acceptance scenarios" "${_ref}"
assert_contains "outcomes reference: a filename match is never moved" "do not move it" "${_ref}"
# Where each source's doc is by Step 7c, after Steps 6 and 7b moved things.
assert_contains "outcomes reference: a recorded doc is found in docs/plans/archive" "| \`state\` | \`docs/plans/archive/<same filename>\`" "${_ref}"
assert_contains "outcomes reference: a change-folder doc is found in the OpenSpec archive" "| \`openspec\` | \`openspec/changes/archive/YYYY-MM-DD-<feature-name>/design.md\`" "${_ref}"
assert_contains "outcomes reference: a missing mapped file is not replaced by a same-named one" "Do not go looking for another file with the same name" "${_ref}"
# Counted, not merely present: a phrase found once would pass with one of two rows lost.
assert_equals "outcomes reference: ambiguous AND stale each ask the user" "2" \
    "$(printf '%s\n' "${_ref}" | grep -c 'ask the user which file is the design doc')"
assert_equals "outcomes reference: ambiguous AND stale each say what to do with the answer" "2" \
    "$(printf '%s\n' "${_ref}" | grep -c 'If the user names a file, generate the report from it')"
assert_equals "outcomes reference: ambiguous AND stale each say what to do with no answer" "2" \
    "$(printf '%s\n' "${_ref}" | grep -c 'If there is no answer, say no Divergences report was written and continue shipping')"
# absent, ambiguous, stale and exit 3 must each end by continuing: none may stall the ship.
assert_equals "outcomes reference: the four non-resolved rows each continue shipping" "4" \
    "$(printf '%s\n' "${_ref}" | grep -E '^\| (`absent`|`ambiguous`|`stale`|exit 3)' | grep -ci 'continue shipping')"
for _bad in "newest" "most recent" "latest"; do
    assert_not_contains "outcomes reference: never told to pick the ${_bad}" "${_bad}" "${_ref}"
    assert_not_contains "Step 7c: never told to pick the ${_bad}" "${_bad}" "${_7c}"
    assert_not_contains "deploy-gate check 4: never told to pick the ${_bad}" "${_bad}" "${_g4}"
done
# Step 7b moves files. It must keep moving ONLY recorded paths: a filename match is
# evidence, not identity, and must never authorise a move. One `mv`, over those four.
assert_contains "Step 7b: still moves the four recorded paths" 'for f in "$discovery_path" "$design_path" "$plan_path" "$spec_path"; do' "${_7b}"
assert_equals "Step 7b: holds exactly one mv" "1" "$(printf '%s\n' "${_7b}" | grep -cF ' mv ')"
assert_not_contains "Step 7b: does not call the resolver" "resolve-design-doc" "${_7b}"
assert_not_contains "Step 7c: moves nothing" " mv " "${_7c}"

export HOME="${_OLDHOME}"
rm -rf "${WORK}"
print_summary
exit $?
