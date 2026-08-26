#!/usr/bin/env bash
# test-hook-source-guards.sh — Static lint for issue #137.
#
# In a hook carrying `trap 'exit 0' ERR`, an UNGUARDED `. lib` is a silent
# early exit: if the lib fails mid-source the trap fires and the hook exits 0.
# For `hooks/openspec-guard.sh` that happens ABOVE the deny checks, so the push
# is silently allowed — the dangerous direction for a safety gate. `bash -n`
# cannot catch this (it is a runtime status, not a parse error), and the
# session-start canary SOURCE-probes only the five `_GATE_ENFORCE_LIBS` at
# runtime, so nothing in the repo gated this class before.
#
# `[ -f "$lib" ]` is NOT a guard: it proves the file exists, and the failure
# under test is a lib that exists but returns non-zero while sourcing.
#
# Guarded forms — a failing source must not be the last command of a list:
#     . lib 2>/dev/null || true
#     . lib && _FLAG=true
#     . lib 2>/dev/null && _FLAG=true || true
#
# SCOPE — WHAT THIS LINT DOES **NOT** COVER. Read before trusting a green run.
#
# The &&/|| exemption suppresses the ERR trap for the `.` builtin's own RETURN
# STATUS. It does NOT suppress the trap when a command *inside* the sourced
# file fails: that trap fires during the sourced file's execution and still
# exits the hook. Measured against the real guard (2026-07-31):
#
#   lib does `return 1` mid-source          -> deny        (covered here)
#   lib sources clean, function undefined   -> deny        (covered here)
#   lib runs `false` mid-source             -> SILENT ALLOW  <-- NOT covered
#   lib hits command-not-found mid-source   -> SILENT ALLOW  <-- NOT covered
#   lib does `X="$(cd /nope && pwd)"`       -> SILENT ALLOW  <-- NOT covered
#
# Those three shapes were issue #192, and it is FIXED — but not here, and that
# distinction is the whole reason to read this paragraph. openspec-guard.sh now
# routes every source through `_guard_load`, which disarms the trap across the
# load; the runtime proof lives in tests/test-hook-source-guard-runtime.sh.
# THIS file's coverage is unchanged: it is static, it inspects call sites, and
# it stayed green through every one of those silent allows. Nothing here
# verifies #192, and widening it to claim so would recreate exactly the
# false-confidence the scope note exists to prevent.
#
# So: a green run here means "no source line can be tripped by its own exit
# status", NOT "no sourced lib can exit this hook".
#
# The other ERR-trap hooks that source libs — compact-recovery-hook.sh,
# compact-recovery-prompt-hook.sh, consolidation-stop.sh, skill-completion-hook.sh,
# skill-gate.sh — still source them directly, so #192's runtime class remains
# OPEN for them. None gates an OUTBOUND action, which is why the fix was scoped
# to the guard: skill-gate.sh does deny, but a silent exit there costs skill
# sequencing rather than letting a push out, and skill-completion-hook.sh fails
# in the safe direction (evidence goes unrecorded, so the push gate denies
# MORE). publish-guard.sh — the other outbound deny — sources nothing at all.
#
# Note that the fix cannot simply be shared: `_guard_load` lives inline in
# openspec-guard.sh because putting it in hooks/lib/ would mean sourcing a lib
# to make sourcing libs safe, and that first source is the one nothing can
# protect. Extending the fix means copying the helper, deliberately.
#
# Population is hooks/*.sh carrying a LOCAL ERR trap. hooks/lib/*.sh are
# deliberately excluded: they carry no trap of their own but execute under the
# caller's, so they are in scope for issue #192, not for this status-only lint.
#
# Bash 3.2 compatible (macOS default). No associative arrays.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures/hook-source-guards"

# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-hook-source-guards.sh ==="
echo ""

# ---------------------------------------------------------------------------
# Allowlist — pre-existing violations, each with a reason (#137).
#
# Keyed by "<basename>|<trimmed source line>", NOT by line number: line numbers
# drift with every unrelated edit above them, which would make the allowlist
# rot silently. Keying on the line's own text means the entry stops matching
# exactly when that line is touched, forcing a fresh decision.
#
# The two gate-critical lines in openspec-guard.sh are deliberately ABSENT —
# they were fixed rather than allowlisted, because that hook's early exit is
# the push-gate bypass this lint exists to prevent.
# ---------------------------------------------------------------------------
ALLOWLIST='consolidation-stop.sh|. "${_PLUGIN_ROOT_TOK}/hooks/lib/session-token.sh"
consolidation-stop.sh|. "${_HELPER_LIB}"
consolidation-stop.sh|. "${_PLUGIN_ROOT_LIB}/hooks/lib/consol-marker.sh"
compact-recovery-hook.sh|. "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
skill-completion-hook.sh|. "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"'

# _unguarded_sources <file> — print "<basename>|<trimmed line>" for each
# unguarded source line, or nothing. Only meaningful for ERR-trap files.
# The matcher covers `.`/`source` AND `_guard_load`, and the second is not
# decoration. #192 routed all 13 gate-critical sources in openspec-guard.sh
# through a `_guard_load` helper; a `.`-only matcher then saw ONE line in that
# file instead of thirteen (measured: 13 at b05925c, 1 after), silently moving
# every site this lint exists to protect out of its own population — while the
# "openspec-guard.sh is never allowlistable" assertion below kept passing,
# vacuously.
#
# The call shape still decides. `_guard_load` returns the source's status, so a
# BARE `_guard_load lib` whose lib fails is a failing simple command at top
# level: ERR trap, exit 0, empty stdout — the identical silent allow, one
# careless call site away. Measured under bash 3.2.57: bare call with a failing
# lib printed nothing and never reached the decision path; the same call with
# `|| true` reached it. So a renamed source is still a source here.
_unguarded_sources() {
    local file="$1" base line trimmed
    base="$(basename "${file}")"
    grep -E '^[[:space:]]*(\.|source|_guard_load)[[:space:]]+' "${file}" 2>/dev/null | while IFS= read -r line; do
        # Strip a trailing comment BEFORE classifying: `. lib  # see foo && bar`
        # would otherwise read as guarded on the comment's `&&`. Stripping for
        # the key too means adding a comment cannot silently invalidate an
        # allowlist entry.
        trimmed="$(printf '%s' "${line}" | sed 's/[[:space:]]#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        # A source that is a non-final operand of an && / || list cannot trip
        # the ERR trap with its own exit status, so it is guarded. See the SCOPE
        # note in the header for what this does NOT prove.
        case "${trimmed}" in
            *'&&'*|*'||'*) continue ;;
        esac
        printf '%s|%s\n' "${base}" "${trimmed}"
    done
}

# _err_trap_hooks — print each hooks/*.sh carrying an ERR trap.
_err_trap_hooks() {
    local f
    for f in "${PROJECT_ROOT}"/hooks/*.sh; do
        [ -f "${f}" ] || continue
        grep -q "trap[[:space:]]*'exit 0'[[:space:]]*ERR" "${f}" 2>/dev/null && printf '%s\n' "${f}"
    done
    return 0
}

# _is_allowed <key>
_is_allowed() {
    case "
${ALLOWLIST}
" in
        *"
$1
"*) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# 0. Sanity: the lint has a non-empty population to inspect. Without this, a
#    glob or grep regression would report "0 violations" and read as success.
# ---------------------------------------------------------------------------
HOOK_FILES="$(_err_trap_hooks)"
HOOK_COUNT="$(printf '%s\n' "${HOOK_FILES}" | grep -c '[^[:space:]]')"
if [ "${HOOK_COUNT}" -ge 5 ]; then
    _record_pass "ERR-trap hook population is non-trivial (${HOOK_COUNT} files)"
else
    _record_fail "ERR-trap hook population is non-trivial" \
        "found only ${HOOK_COUNT} — the detector or the glob is broken, not the repo"
fi

# ---------------------------------------------------------------------------
# 1. No unguarded source lines outside the allowlist.
# ---------------------------------------------------------------------------
VIOLATIONS=""
ALL_KEYS=""
while IFS= read -r hook; do
    [ -n "${hook}" ] || continue
    while IFS= read -r key; do
        [ -n "${key}" ] || continue
        ALL_KEYS="${ALL_KEYS}${key}
"
        _is_allowed "${key}" || VIOLATIONS="${VIOLATIONS}${key}
"
    done <<EOF
$(_unguarded_sources "${hook}")
EOF
done <<EOF
${HOOK_FILES}
EOF

if [ -z "${VIOLATIONS}" ]; then
    _record_pass "no unguarded \`source\` in ERR-trap hooks outside the allowlist"
else
    _record_fail "no unguarded \`source\` in ERR-trap hooks outside the allowlist" \
        "$(printf '%s' "${VIOLATIONS}" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 2. The allowlist must not rot: every entry must still match a real violation.
#    Without this, a fixed line leaves a permanent blanket exemption behind and
#    the allowlist slowly becomes a way to never fail.
# ---------------------------------------------------------------------------
STALE=""
while IFS= read -r entry; do
    [ -n "${entry}" ] || continue
    case "
${ALL_KEYS}" in
        *"
${entry}
"*) ;;
        *) STALE="${STALE}${entry} " ;;
    esac
done <<EOF
${ALLOWLIST}
EOF

if [ -z "${STALE}" ]; then
    _record_pass "allowlist has no stale entries"
else
    _record_fail "allowlist has no stale entries" \
        "these no longer match a violation and must be removed: ${STALE}"
fi

# ---------------------------------------------------------------------------
# 3. The two gate-critical openspec-guard.sh lines are NOT allowlisted.
#    Pins the #137 decision so a future edit cannot quietly exempt them.
# ---------------------------------------------------------------------------
case "${ALLOWLIST}" in
    *"openspec-guard.sh|"*)
        _record_fail "openspec-guard.sh is never allowlisted" \
            "the push-gate hook's early exit is the bypass this lint exists to prevent" ;;
    *)
        _record_pass "openspec-guard.sh is never allowlisted" ;;
esac

# ---------------------------------------------------------------------------
# 4. Red/green fixtures — the detector must actually detect.
# ---------------------------------------------------------------------------
RED="${FIXTURES}/red-unguarded.sh"
GREEN="${FIXTURES}/green-guarded.sh"

if [ -f "${RED}" ] && [ -f "${GREEN}" ]; then
    red_hits="$(_unguarded_sources "${RED}")"
    assert_not_empty "red fixture is flagged by the lint" "${red_hits}"

    green_hits="$(_unguarded_sources "${GREEN}")"
    if [ -z "${green_hits}" ]; then
        _record_pass "green fixture is not flagged by the lint"
    else
        _record_fail "green fixture is not flagged by the lint" "flagged: ${green_hits}"
    fi

    # ------------------------------------------------------------------
    # 5. The fixtures must be a REAL bypass, not just a lint target.
    #    Both exit 0 — that is the silent-failure signature — so the exit
    #    code cannot distinguish them. Assert on reaching the decision.
    # ------------------------------------------------------------------
    red_out="$(bash "${RED}" 2>/dev/null)"
    assert_not_contains "red fixture never reaches its deny decision (the bypass)" \
        "DENY_REACHED" "${red_out}"

    green_out="$(bash "${GREEN}" 2>/dev/null)"
    assert_contains "green fixture still reaches its deny decision" \
        "DENY_REACHED" "${green_out}"
else
    _record_fail "red/green fixtures exist" "missing ${RED} or ${GREEN}"
fi

# ---------------------------------------------------------------------------
# 6. End-to-end on the REAL guard: with hooks/lib/session-token.sh failing
#    mid-source, openspec-guard.sh must still reach its push decision.
#    This is the assertion that goes red against the pre-#137 guard.
# ---------------------------------------------------------------------------
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
E2E_TMP="$(mktemp -d "${TMPDIR:-/tmp}/acs-src-guard.XXXXXXXX")" || E2E_TMP=""
if [ -n "${E2E_TMP}" ] && [ -d "${E2E_TMP}" ] && [ -f "${GUARD}" ]; then
    # A plugin root whose session-token.sh exists but fails while sourcing.
    mkdir -p "${E2E_TMP}/root/hooks/lib"
    cp "${PROJECT_ROOT}"/hooks/lib/*.sh "${E2E_TMP}/root/hooks/lib/" 2>/dev/null
    cat > "${E2E_TMP}/root/hooks/lib/session-token.sh" <<'BROKEN'
#!/bin/bash
# Exists (so `[ -f ]` passes) but fails mid-source, leaving the resolver undefined.
return 1
resolve_session_token_from_transcript() { echo "never-defined"; }
BROKEN

    # A HOME carrying the singleton the guard must fall back to.
    mkdir -p "${E2E_TMP}/home/.claude"
    printf 'session-srcguard-fixture\n' > "${E2E_TMP}/home/.claude/.skill-session-token"

    # Own fixture repo (never the checkout): diff-dependent legs need one.
    mkdir -p "${E2E_TMP}/repo"
    (
        cd "${E2E_TMP}/repo" || exit 1
        git init -q 2>/dev/null
        git config user.email t@t.t; git config user.name t
        echo x > f.txt; git add f.txt; git commit -qm init 2>/dev/null
    )

    _run_guard() {
        (cd "${E2E_TMP}/repo" && printf '%s' \
            '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
            | HOME="${E2E_TMP}/home" CLAUDE_PLUGIN_ROOT="${E2E_TMP}/root" \
              bash "${GUARD}" 2>/dev/null)
    }

    e2e_out="$(_run_guard)"

    # Pre-fix, the unguarded source tripped the ERR trap here and the hook
    # exited 0 with EMPTY stdout — indistinguishable from "allow".
    assert_contains "guard still reaches its push decision when the token lib fails mid-source" \
        "permissionDecision" "${e2e_out}"

    # Match the REAL producer's bytes, not the bare word: the guard emits deny
    # JSON via `jq -n`, which PRETTY-prints (space after the colon, own line).
    # A bare "deny" needle is satisfied by the ALLOW path too — the IMPLEMENT
    # advisory at openspec-guard.sh:493 contains the literal text
    # "will become a deny after backtest", so the old assertion could pass on
    # an allow. Same lesson as the push-gate-capture classifier.
    assert_contains "guard denies rather than falling open on a broken token lib" \
        '"permissionDecision": "deny"' "${e2e_out}"

    # The `command -v` leg is load-bearing, so it needs its own pin: a lib that
    # sources CLEANLY but never defines the resolver. Without this assertion the
    # `command -v` clause can be deleted and the whole suite still passes, while
    # the bypass silently reopens (verified: that mutant passed 10/10).
    cat > "${E2E_TMP}/root/hooks/lib/session-token.sh" <<'NOFUNC'
#!/bin/bash
# Sources cleanly, exit status 0, but never defines the resolver.
_SESSION_TOKEN_LIB_LOADED=true
NOFUNC
    nofunc_out="$(_run_guard)"
    assert_contains "guard reaches its decision when the lib omits the resolver" \
        '"permissionDecision": "deny"' "${nofunc_out}"
else
    if [ -n "${E2E_TMP}" ] && [ -d "${E2E_TMP}" ]; then
        _record_fail "e2e broken-lib fixture builds" "guard not found at ${GUARD}"
    else
        _record_fail "e2e broken-lib fixture builds" "mktemp failed"
    fi
fi
# Unconditional: the success branch is not the only path that created the dir.
[ -n "${E2E_TMP}" ] && [ -d "${E2E_TMP}" ] && rm -rf "${E2E_TMP}" 2>/dev/null

print_summary
