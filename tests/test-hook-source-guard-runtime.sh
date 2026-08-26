#!/usr/bin/env bash
# test-hook-source-guard-runtime.sh — issue #192.
#
# #137 guarded every `. lib` call site in hooks/openspec-guard.sh so a lib that
# returns non-zero cannot trip `trap 'exit 0' ERR`. That fix is real but
# STATUS-ONLY: the `&&`/`||` exemption suppresses the trap for the `.` builtin's
# own return status, and NOT for a command that fails *inside* the sourced file.
# That trap fires during the sourced file's execution, above every deny check,
# so the hook exits 0 with EMPTY STDOUT — which the harness cannot distinguish
# from a deliberate allow. For a push gate that is the one failure direction
# that matters.
#
# Measured at b05925c with a `git push origin HEAD` payload, varying ONLY how a
# lib fails (one fault at a time, gate state otherwise identical):
#
#   healthy                                    -> deny            (460 bytes)
#   lib does `return 1`                        -> deny / advisory  (#137, ok)
#   lib runs `false`                           -> EMPTY STDOUT  <- silent allow
#   lib hits command-not-found                 -> EMPTY STDOUT  <- silent allow
#   lib does `X="$(cd /nope && pwd)"`          -> EMPTY STDOUT  <- silent allow
#
# The last shape is live in this repo at hooks/lib/phase-evidence.sh:10.
#
# WHY THIS TEST EXISTS SEPARATELY FROM tests/test-hook-source-guards.sh: that
# one is a STATIC, status-only lint and says so in its own header. It stays
# green through every silent allow in the table above, because the call sites
# it inspects are correctly guarded — the defect is runtime, so the test has to
# be runtime too. Do not merge the two.
#
# WHY A DISPOSABLE PLUGIN ROOT AND NOT A /tmp COPY OF THE HOOK: the guard
# derives _PLUGIN_ROOT from $0 when CLAUDE_PLUGIN_ROOT is unset, so a bare copy
# silently changes which libs it finds and fabricates the difference under
# test. Every run below copies the WHOLE tree and sets CLAUDE_PLUGIN_ROOT at it
# explicitly, exactly as tests/test-push-gate-degradation-advisory.sh does.
#
# WHY A CLEAN VERDICT IS SEEDED: this repo IS a routing repo and this branch
# touches hooks/, so routing-governance would deny every push for a reason
# unrelated to what is being measured, masking the fault cells.
#
# Bash 3.2 compatible (macOS default). No associative arrays.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures/hook-source-guard-runtime"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-hook-source-guard-runtime.sh ==="
echo ""

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq unavailable — this test reads the guard's JSON decision."
    # `print_summary` RETURNS, it does not exit. Without the explicit exit the
    # SKIP printed a zero-test summary and then ran the whole matrix anyway,
    # failing ~80 assertions on a machine without jq — a skip that did not skip.
    print_summary
    exit $?
fi

# Every cell is measured against the healthy control's DENY, so an inherited
# bypass would not fail loudly — it would make the whole matrix compare one
# allow against another. The healthy assertion below would catch it, but only
# after the reader spent a while wondering why; unsetting it is cheaper.
unset ACSM_SKIP_PUSH_GATE

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/hsgr-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"     # basename "t" -> token "session-t"
_TOK="session-t"

# Disposable plugin root — libs get broken in HERE, never in the checkout.
_TROOT="$(mktemp -d /tmp/hsgr-root-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks"  "${_TROOT}/hooks"
cp -R "${PROJECT_ROOT}/config" "${_TROOT}/config" 2>/dev/null || true

_cleanup() { export HOME="$_OLDHOME"; rm -rf "${_TROOT}"; }
trap _cleanup EXIT

_HEAD="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
jq -nc --arg s "${_HEAD}" \
    '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
    > "${HOME}/.claude/.skill-project-verified-${_TOK}"

_input() {
    jq -n --arg tp "$_TPATH" --arg cmd "git push origin HEAD" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}

run() {
    ( cd "${PROJECT_ROOT}" && _input | \
        CLAUDE_PLUGIN_ROOT="${_TROOT}" bash "${_TROOT}/hooks/openspec-guard.sh" 2>/dev/null )
}

# _inject <lib> <fixture> <early|late>
#
# early = after the shebang, BEFORE the lib defines anything.
# late  = appended, AFTER every definition — the cleanest proof that what kills
#         the hook is the ERR trap and not a missing function.
#
# Asserts the write actually changed the file. A fixture that silently failed
# to apply turns every cell into a healthy run, i.e. a green suite that pins
# nothing — the exact way this class of test goes vacuous.
_inject() {
    _ij_lib="${_TROOT}/hooks/lib/$1"
    _ij_orig="${PROJECT_ROOT}/hooks/lib/$1"
    cp "${_ij_orig}" "${_ij_lib}"
    if [ "$3" = "early" ]; then
        { head -1 "${_ij_orig}"; cat "${FIXTURES}/$2"; tail -n +2 "${_ij_orig}"; } > "${_ij_lib}"
    else
        cat "${FIXTURES}/$2" >> "${_ij_lib}"
    fi
    if cmp -s "${_ij_orig}" "${_ij_lib}"; then
        _record_fail "injection applied: $2 ($3) into $1" "file is unchanged"
    fi
}

_restore() { cp "${PROJECT_ROOT}/hooks/lib/$1" "${_TROOT}/hooks/lib/$1"; }

# ---------------------------------------------------------------------------
# Healthy control. Every fault cell is compared against THIS run's bytes rather
# than a hardcoded string, so the test measures "the fault changed the outcome"
# and not "the gate still says what it said in 2026".
# ---------------------------------------------------------------------------
_HEALTHY="$(run)"
assert_not_empty "healthy control produces output at all" "${_HEALTHY}"
assert_equals "healthy control denies the push" "deny" \
    "$(printf '%s' "${_HEALTHY}" | jq -r '.hookSpecificOutput.permissionDecision // "NONE"' 2>/dev/null)"
assert_equals "healthy control is stable across two runs" "${_HEALTHY}" "$(run)"

# ---------------------------------------------------------------------------
# The #192 matrix. Every gate-enforcement lib the guard sources, plus
# phase-attest.sh: the issue notes that fixing only the token site is
# insufficient because phase-attest.sh:56 re-sources session-token.sh and the
# re-armed trap fires there instead.
#
# EXPECTATION, POST-FIX — two outcomes are correct and the injection point is
# what decides which. Both are pinned; neither is "not empty", which would also
# pass if a fault silently downgraded a deny into an advisory.
#
#   early — the fault lands BEFORE the definitions. With the trap cleared,
#           sourcing CONTINUES past the failing command, so every function is
#           defined anyway and the guard must reach the healthy decision. This
#           is the whole point of the fix.
#
#   late  — the fault lands after the definitions, so it is also the source's
#           LAST command and the source's exit status is non-zero. #137's
#           `_guard_load … && FLAG=true` form reads that status as "did not
#           load" even though every function is present, so the guard degrades
#           exactly as it does when the lib is ABSENT: loudly (#198), never
#           silently. That is a status-predicate question, deliberately settled
#           in #198 (which rejected switching branch-ledger.sh's site to a
#           `command -v` predicate because it would weaken a deny), and NOT
#           #192's to reopen — so this asserts the documented behaviour rather
#           than a decision the fix has no business making.
#
# Each cell must therefore be byte-identical to one of TWO baselines, both
# captured from the real guard in this same state. Which baseline is not
# hardcoded per lib: the absent-lib run already collapses to the healthy output
# wherever losing that lib costs no decision (a deny swallows the advisory), so
# naming the pair is both accurate and self-maintaining.
# ---------------------------------------------------------------------------
_LIBS="git-command.sh session-token.sh branch-ledger.sh verdict.sh phase-evidence.sh phase-attest.sh"
_FAULTS="fault-false.sh fault-command-not-found.sh fault-cmdsubst-cd.sh"

# _assert_cell <label> <out> <absent-baseline>
#
# NAMING IS LOAD-BEARING HERE. For session-token.sh and branch-ledger.sh the
# absent-lib baseline is an ALLOW where healthy is a DENY, so six of these cells
# pass on a run that lets the push through. That is #198's designed posture —
# for a late-position fault in those libs, #192 converts a SILENT bypass into an
# ANNOUNCED one, and the push still goes out — but a label reading
# "healthy-or-announced-degradation" would let 85/85 be misread as "the gate
# held in all 85 cells". It did not, and the assertion says which it is.
_assert_cell() {
    local _ac_kind
    assert_not_empty "$1: guard is not silent" "$2"
    if [ "$2" = "${_HEALTHY}" ]; then
        _ac_kind="healthy deny"
    elif [ -n "$3" ] && [ "$2" = "$3" ]; then
        _ac_kind="announced degradation (push ALLOWED, as when the lib is absent)"
    else
        _record_fail "$1: outcome is a healthy deny, or the same announced degradation as an absent lib" \
            "got: [$2]"
        return 0
    fi
    _record_pass "$1: outcome is ${_ac_kind}"
}

for _lib in ${_LIBS}; do
    # Baseline for this lib: what the guard does when it is simply not there.
    # Derived from the real guard, not written by hand — a hand-written
    # expectation only proves the test agrees with itself.
    rm -f "${_TROOT}/hooks/lib/${_lib}"
    _ABSENT="$(run)"
    _restore "${_lib}"
    assert_not_empty "${_lib} absent: baseline is itself non-silent" "${_ABSENT}"

    for _fault in ${_FAULTS}; do
        _inject "${_lib}" "${_fault}" "early"
        _out="$(run)"
        _restore "${_lib}"
        assert_not_empty "${_lib} + ${_fault} (early): guard is not silent" "${_out}"
        assert_equals \
            "${_lib} + ${_fault} (early): sourcing continued, decision is healthy" \
            "${_HEALTHY}" "${_out}"

        _inject "${_lib}" "${_fault}" "late"
        _out="$(run)"
        _restore "${_lib}"
        _assert_cell "${_lib} + ${_fault} (late)" "${_out}" "${_ABSENT}"
    done
done

# ---------------------------------------------------------------------------
# One cell asserted positively rather than by baseline equality. The matrix
# above accepts "healthy OR absent-lib", which is right but leaves a reader
# unable to tell whether the announced-degradation branch was ever actually
# exercised — a union assertion is satisfied by whichever half happens to fire.
# session-token.sh is the lib whose loss visibly changes the outcome, so pin
# there that the late-fault path really does reach #198's advisory, by name.
# ---------------------------------------------------------------------------
_inject "session-token.sh" "fault-false.sh" "late"
_late="$(run)"
_restore "session-token.sh"
assert_contains "late fault announces the degradation rather than going silent" \
    "GATE DEGRADED" "$(printf '%s' "${_late}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
assert_contains "the advisory names the lib that did not load" \
    "session-token.sh" "$(printf '%s' "${_late}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"

# ---------------------------------------------------------------------------
# Mechanism 1: the `trap - ERR` line itself.
#
# `_guard_load` is protected TWICE over — by the explicit trap disarm, and by
# being a function at all, since bash does not inherit an ERR trap into a
# function without `set -E`. The guard has no `set -E`, so in the shipped
# configuration mechanism 2 carries the fix alone and **deleting the `trap -
# ERR` line leaves the entire matrix above green** (measured: 85/85). Anyone
# "simplifying" the helper by dropping it therefore gets a clean CI run, and the
# comment in the guard calling both mechanisms deliberate would be describing
# something no test defends.
#
# So pin it where it is load-bearing: under `set -E`. The function body is
# EXTRACTED FROM THE REAL GUARD rather than restated here — a hand-copied helper
# would only prove this test agrees with itself, and would keep passing after
# the real one changed. The extraction is asserted to have worked, because a
# failed extraction would silently make every assertion below vacuous.
# ---------------------------------------------------------------------------
_GL_SRC="$(sed -n '/^_guard_load() {/,/^}/p' "${PROJECT_ROOT}/hooks/openspec-guard.sh")"
assert_contains "extracted the real _guard_load from the guard" "_gl_rc" "${_GL_SRC:-<empty>}"

_gl_drive() {   # $1 = the helper text to install; prints END if the driver survived
    local d="${_TROOT}/gl_drive.sh" lib="${_TROOT}/gl_badlib.sh"
    printf '# lib that FAILS mid-source (the #192 shape)\nfalse\n_gl_probe() { :; }\n' > "${lib}"
    {   printf 'set -E\n'
        printf "trap 'exit 0' ERR\n"
        printf '%s\n' "$1"
        printf '_guard_load "%s" || true\n' "${lib}"
        printf 'echo END\n'
    } > "${d}"
    /bin/bash "${d}" 2>/dev/null
}

assert_equals "under set -E, the real _guard_load survives a lib failing mid-source" \
    "END" "$(_gl_drive "${_GL_SRC}")"

# Red control for the cell above: strip ONLY the trap disarm from the same
# extracted text. If this still prints END, the assertion above is not measuring
# the trap line and this whole cell is decoration.
_GL_NOTRAP="$(printf '%s\n' "${_GL_SRC}" | grep -v '^[[:space:]]*trap - ERR[[:space:]]*$')"
if [ "${_GL_SRC}" = "${_GL_NOTRAP}" ]; then
    _record_fail "red control: the trap-disarm line was actually removed" \
        "stripping 'trap - ERR' changed nothing — the extraction or the helper no longer contains it"
else
    _record_pass "red control: the trap-disarm line was actually removed"
fi
assert_equals "…and without that line the same helper is killed by the inherited trap" \
    "" "$(_gl_drive "${_GL_NOTRAP}")"

# ---------------------------------------------------------------------------
# Red control — `return 1` is NOT a #192 shape. It aborts the source, so the
# lib is genuinely unloaded and the guard degrades exactly as it does for an
# absent lib (#198): an advisory, possibly no decision. What it must never do
# is go silent. If this control ever starts matching the healthy control, the
# harness has stopped injecting anything and the matrix above is vacuous.
# ---------------------------------------------------------------------------
_inject "session-token.sh" "control-return-1.sh" "early"
_ctl="$(run)"
_restore "session-token.sh"
assert_not_empty "control: aborted source still announces itself" "${_ctl}"
if [ "${_ctl}" = "${_HEALTHY}" ]; then
    _record_fail "control: an aborted source is distinguishable from healthy" \
        "output is byte-identical to the healthy control — injection is a no-op"
else
    _record_pass "control: an aborted source is distinguishable from healthy"
fi

print_summary
