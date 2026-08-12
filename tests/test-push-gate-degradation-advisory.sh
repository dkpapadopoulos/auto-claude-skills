#!/usr/bin/env bash
# test-push-gate-degradation-advisory.sh — issue #198.
#
# The push gate is deliberately fail-OPEN on infrastructure error: when a
# gate-enforcement lib cannot load, the legs that depend on it are skipped and
# the push is allowed. That is the right direction — a check that cannot run
# must never block. What was wrong is that it happened in COMPLETE SILENCE:
# measured at da651b5, four distinct lib-load faults produced EMPTY stdout,
# which the harness cannot distinguish from a deliberate allow. The user is
# told nothing, so a permanently degraded plugin install looks exactly like a
# clean gate that keeps passing.
#
# This test pins the advisory AND, equally importantly, pins that adding it
# changed no `permissionDecision` anywhere in the matrix.
#
# WHY A REAL CHECKOUT, NOT A /tmp COPY OF THE GUARD: openspec-guard.sh derives
# `_PLUGIN_ROOT` from `$0` when CLAUDE_PLUGIN_ROOT is unset, so a bare /tmp
# copy silently changes which libs it can find and fabricates the very
# difference under test. Every run below sets CLAUDE_PLUGIN_ROOT explicitly at
# a full copied tree.
#
# Bash 3.2 compatible (macOS default). No associative arrays.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures/guard-lib-fault"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-degradation-advisory.sh ==="
echo ""

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgd-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"     # basename "t" -> token "session-t"

# Disposable plugin root — libs get broken in here, never in the checkout.
_TROOT="$(mktemp -d /tmp/pgd-root-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks"  "${_TROOT}/hooks"
cp -R "${PROJECT_ROOT}/config" "${_TROOT}/config" 2>/dev/null || true

_cleanup() { export HOME="$_OLDHOME"; rm -rf "${_TROOT}"; }
trap _cleanup EXIT

_input() {
    jq -n --arg tp "$_TPATH" --arg cmd "${1:-git push origin HEAD}" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}

# run [plugin_root] — always from the real checkout, explicit CLAUDE_PLUGIN_ROOT.
run() {
    ( cd "${PROJECT_ROOT}" && _input | \
        CLAUDE_PLUGIN_ROOT="${1:-${_TROOT}}" bash "${_TROOT}/hooks/openspec-guard.sh" 2>/dev/null )
}

# Live ~/.claude state is mutable, so a single run can differ from the next for
# reasons unrelated to the fault. Every cell runs twice and the pair must agree.
run_stable() {
    local a b
    a="$(run "${1:-${_TROOT}}")"
    b="$(run "${1:-${_TROOT}}")"
    if [ "$a" != "$b" ]; then
        printf '%s' "NON-DETERMINISTIC:${a}|${b}"
        return 0
    fi
    printf '%s' "$a"
}

_restore_ledger() { cp "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh" "${_TROOT}/hooks/lib/branch-ledger.sh"; }
_restore_verdict() { cp "${PROJECT_ROOT}/hooks/lib/verdict.sh"       "${_TROOT}/hooks/lib/verdict.sh"; }

# ---------------------------------------------------------------------------
# Cell 5 — healthy control. Must be BYTE-IDENTICAL to the recorded baseline and
# must not mention degradation. This is the no-regression clause of the issue's
# A/B contract; the fixture is the pinned never-delete artifact.
# ---------------------------------------------------------------------------
out="$(run_stable)"
if [ -f "${FIXTURES}/healthy-control.json" ]; then
    expected="$(cat "${FIXTURES}/healthy-control.json")"
    assert_equals "healthy control is byte-identical to the pinned baseline" \
        "${expected}" "${out}"
else
    _record_fail "healthy-control fixture exists" "missing ${FIXTURES}/healthy-control.json"
fi
assert_not_contains "healthy control emits no degradation advisory" \
    "GATE DEGRADED" "${out:-}"

# ---------------------------------------------------------------------------
# Cell 2 — branch-ledger.sh absent. Every ledger leg and the whole global
# fail-closed gate stop being enforced. Baseline: empty stdout.
# ---------------------------------------------------------------------------
rm -f "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"
assert_contains     "absent ledger lib => degradation advisory" "GATE DEGRADED"     "${out:-<empty>}"
assert_contains     "advisory names the lib that did not load"  "branch-ledger.sh"  "${out:-<empty>}"
assert_not_contains "absent ledger lib still falls OPEN"        '"deny"'            "${out:-}"
_restore_ledger

# ---------------------------------------------------------------------------
# Cell 3 — branch-ledger.sh returns non-zero mid-source. `[ -f "$lib" ]` says
# the file is fine; the source still fails. Baseline: empty stdout.
# ---------------------------------------------------------------------------
printf '\nreturn 1\n' >> "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"
assert_contains     "failing ledger source => degradation advisory" "GATE DEGRADED"    "${out:-<empty>}"
assert_contains     "advisory names the lib that did not load"      "branch-ledger.sh" "${out:-<empty>}"
assert_not_contains "failing ledger source still falls OPEN"        '"deny"'           "${out:-}"
_restore_ledger

# ---------------------------------------------------------------------------
# Cell 1 — plugin root unresolvable. This is the memory-evidenced shape: the
# guard resolved its root to a directory with no hooks/lib, so session-token.sh
# is unreachable too and the hook exits before any gate runs. Covering only
# branch-ledger.sh would leave THIS case silent, which is why the token path is
# in scope.
# ---------------------------------------------------------------------------
_EMPTY_ROOT="$(mktemp -d /tmp/pgd-empty-XXXXXX)"
out="$(run_stable "${_EMPTY_ROOT}")"
assert_contains     "unresolvable plugin root => degradation advisory" "GATE DEGRADED"    "${out:-<empty>}"
assert_contains     "advisory names the token lib"                     "session-token.sh" "${out:-<empty>}"
assert_not_contains "unresolvable plugin root still falls OPEN"        '"deny"'           "${out:-}"
rm -rf "${_EMPTY_ROOT}"

# ---------------------------------------------------------------------------
# Cell 7 — verdict.sh absent while the gate otherwise PASSES. Cell 6 below
# shows why this cell is needed: when a deny fires, the guard's one-JSON-object
# contract means the advisory cannot also be emitted, so the verdict advisory
# is only observable on a passing push.
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
branch_ledger_record "requesting-code-review"         "${PROJECT_ROOT}"
branch_ledger_record "verification-before-completion" "${PROJECT_ROOT}"
rm -f "${_TROOT}/hooks/lib/verdict.sh"
out="$(run_stable)"
assert_contains     "absent verdict lib on a passing push => advisory" "GATE DEGRADED" "${out:-<empty>}"
assert_contains     "advisory names the verdict lib"                   "verdict.sh"    "${out:-<empty>}"
assert_not_contains "absent verdict lib still falls OPEN"              '"deny"'        "${out:-}"
_restore_verdict

# Drop the seeded evidence again for the deny-direction pins below.
_bl_dir="$(branch_ledger_dir "${PROJECT_ROOT}" 2>/dev/null || true)"
[ -n "${_bl_dir}" ] && [ -d "${_bl_dir}" ] && rm -rf "${_bl_dir}"

# ---------------------------------------------------------------------------
# Cell 6 — verdict.sh absent with NO evidence. The global fail-closed gate
# denies first and exits, so the advisory is deliberately not emitted: the
# guard may put at most one JSON object on stdout, and the user is already
# being stopped. Pinned so the deny is not lost to a future refactor.
# ---------------------------------------------------------------------------
rm -f "${_TROOT}/hooks/lib/verdict.sh"
out="$(run_stable)"
assert_contains "absent verdict lib + no evidence still DENIES" '"deny"' "${out:-<empty>}"
_restore_verdict

# ---------------------------------------------------------------------------
# Cell 4 — branch-ledger.sh sources cleanly but defines no functions. This
# DENIES today (the undefined call is used as `cmd && flag=true`, so it is a
# handled failure, not an ERR-trap exit) and it must KEEP denying.
#
# CLAUDE.md's mandated guard form is source + `command -v <fn>` + flag, and
# branch-ledger.sh does not use it. Adding it here would set _LEDGER_OK=false
# and collapse this cell into cell 2 — turning a DENY into an ALLOW. That is a
# real weakening of enforcement, so it is deliberately NOT done: the issue's
# no-regression clause forbids changing any permissionDecision. The deny
# message names the wrong remedy ("no record exists" when the truth is "could
# not check"), which is a separate, non-silent problem.
# ---------------------------------------------------------------------------
: > "${_TROOT}/hooks/lib/branch-ledger.sh"
echo '# sources cleanly, defines nothing' >> "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"
assert_contains "partially-loaded ledger lib still DENIES (must not weaken)" \
    '"deny"' "${out:-<empty>}"
_restore_ledger

# ---------------------------------------------------------------------------
# Cell 3b — branch-ledger.sh runs `false` mid-source. KNOWN NOT COVERED: the
# ERR trap fires DURING the source, so the hook exits before any accumulator
# could be read. That shape needs `trap - ERR` around every lib-loading region
# and is tracked as issue #192. Only the fail-open direction is pinned here, so
# this assertion does not fight #192 when it lands.
# ---------------------------------------------------------------------------
printf '\nfalse\n' >> "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"
assert_not_contains "ERR-trap-exiting lib still falls OPEN (#192 boundary)" '"deny"' "${out:-}"
_restore_ledger

# ---------------------------------------------------------------------------
# The advisory must never carry a permissionDecision of its own: a decision on
# the advisory channel would auto-approve the command and suppress every
# downstream warning (documented bug shape in the guard).
# ---------------------------------------------------------------------------
rm -f "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"
assert_not_contains "degradation advisory carries no permissionDecision" \
    "permissionDecision" "${out:-}"
assert_contains     "degradation advisory rides the additionalContext channel" \
    "additionalContext" "${out:-<empty>}"
_restore_ledger

print_summary
