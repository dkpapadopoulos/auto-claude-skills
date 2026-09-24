#!/usr/bin/env bash
# tests/test-push-gate-heredoc-remedy.sh — #231 (interpreter-heredoc half)
#
# A command whose heredoc body merely MENTIONS a push is denied, and told to run
# `requesting-code-review` — for a command that pushes nothing. All five denies
# measured at v3.86.1 pushed nothing, so on that population the remedy was wrong
# every time.
#
# WHAT THIS FIXES AND WHAT IT DELIBERATELY DOES NOT. It fixes the REMEDY: the
# deny now names the heredoc owner and says why the text is read as a push. It
# does NOT narrow detection, because an interpreter heredoc's body is a PROGRAM
# and `os.system("git push")` inside it really pushes — so "the match is inside
# a heredoc, therefore inert" is false for exactly these owners. Narrowing would
# trade a security property for ergonomics, which #231 records as a decision
# needing explicit acceptance rather than a quiet fix.
#
# The asymmetry with #222 is the whole point and is asserted below: a `cat`
# heredoc body is DATA and is consumed, so it never reaches push detection; a
# `python3` body is unmodellable, so the parse is marked untrusted and detection
# falls back to substring.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-heredoc-remedy.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
NEEDLE="whose body this gate cannot model"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq unavailable — this file drives the real guard and cannot degrade"; exit 1
fi

_OLDHOME="$HOME"
TMP="$(mktemp -d /tmp/pghd-XXXXXX)"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
_TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"
REPO="${TMP}/repo"; mkdir -p "${REPO}"
( cd "${REPO}"; git init -q; git config user.email t@t; git config user.name t
  echo a > f; git add -A; git commit -qm c1 )

# _run <command> -> guard stdout
_run() {
    jq -nc --arg tp "${_TPATH}" --arg c "$1" \
        '{transcript_path:$tp,tool_input:{command:$c}}' \
      | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null )
}
_reason() { printf '%s' "${1:-}" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
_decision() { printf '%s' "${1:-}" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }

PY_CMD="$(printf 'python3 - <<PY\nprint(1)\n# git push origin main\nPY')"
CAT_CMD="$(printf 'cat > plan.md <<EOF\ngit push origin main\nEOF')"
PLAIN_CMD='git push origin main'

test_interpreter_heredoc_deny_explains_itself() {
    local out reason
    out="$(_run "${PY_CMD}")"
    reason="$(_reason "${out}")"
    assert_equals   "the interpreter-heredoc command still denies" "deny" "$(_decision "${out}")"
    assert_contains "the deny says why the text is read as a push" "${NEEDLE}" "${reason:-<empty>}"
    assert_contains "the deny names the heredoc owner"             'python3'  "${reason:-<empty>}"
}

test_the_decision_is_unchanged() {
    # THE SECURITY ASSERTION. The remedy improved; detection did not narrow. A
    # body that really pushes is not distinguishable from one that does not, so
    # the deny must survive this change.
    assert_equals "detection was not narrowed by the better message" \
        "deny" "$(_decision "$(_run "${PY_CMD}")")"
}

test_a_data_sink_heredoc_is_not_a_push_at_all() {
    # #222's half: a `cat` body is DATA and is consumed, so it never reaches
    # push detection.
    #
    # PAIRED WITH A POSITIVE CONTROL, because the assertion is on the ABSENCE of
    # a deny and the guard's output for this command is EMPTY. Found in review:
    # the first version passed with hooks/openspec-guard.sh replaced by
    # `exit 0` — it could not tell "allowed" from "the guard never ran", which
    # is the empty-output failure CLAUDE.md names in the publish-guard bullet.
    # The control runs in the SAME harness, so a guard that is not executing
    # fails it and the absence assertion below is never read as evidence.
    local ctrl
    ctrl="$(_run "${PLAIN_CMD}")"
    if [ "$(_decision "${ctrl}")" = "deny" ]; then
        _record_pass "CONTROL: the guard is executing in this harness"
    else
        _record_fail "CONTROL: the guard is executing in this harness" \
            "a plain push did not deny — every absence assertion here is vacuous"
        return
    fi
    assert_not_contains "a cat-heredoc mentioning a push does not deny" \
        '"deny"' "$(_run "${CAT_CMD}")"
}

test_control_a_real_push_gets_no_heredoc_note() {
    # Without this, a note appended unconditionally would pass every cell above.
    local out reason
    out="$(_run "${PLAIN_CMD}")"
    reason="$(_reason "${out}")"
    assert_equals       "CONTROL: a plain push still denies"      "deny"      "$(_decision "${out}")"
    assert_not_contains "CONTROL: and carries no heredoc note"    "${NEEDLE}" "${reason:-}"
}

test_a_real_push_beside_a_data_sink_heredoc_gets_no_note() {
    # The sharper control. `cat`-heredoc alone never reaches push detection, so
    # recording an owner for it changes nothing observable and a mutation that
    # did so failed no cell — measured. This command IS a push AND carries a
    # data-sink heredoc, so the note can only be absent if the owner is
    # recorded for UNKNOWN owners only.
    local reason
    reason="$(_reason "$(_run "$(printf 'git push origin main && cat > plan.md <<EOF\nnotes\nEOF')")")"
    assert_not_contains "a push beside a cat-heredoc carries no heredoc note" \
        "${NEEDLE}" "${reason:-}"
}

test_the_owner_reader_is_message_material_only() {
    # Nothing may gate on it. A predicate that decided on heredoc ownership
    # would be the narrowing this file exists to say was not done.
    # Count INVOCATIONS, not mentions: the `command -v` presence check names it
    # too, and the first cut of this cell counted that as a second call site.
    local hits
    hits="$(grep -c '\$(command_untrusted_heredoc_owner' "${GUARD}" || true)"
    assert_equals "the guard invokes the owner reader exactly once" "1" "${hits}"
    if grep -n 'command_untrusted_heredoc_owner' "${GUARD}" | grep -qE '_PUSHGATE_SKIP|_DECISION|permissionDecision|exit'; then
        _record_fail "the owner reader never touches a decision" \
            "found it on a line that also mentions a decision, skip or exit"
    else
        _record_pass "the owner reader never touches a decision"
    fi
}

assert_test_functions_wired "$0"

test_interpreter_heredoc_deny_explains_itself
test_the_decision_is_unchanged
test_a_data_sink_heredoc_is_not_a_push_at_all
test_control_a_real_push_gets_no_heredoc_note
test_a_real_push_beside_a_data_sink_heredoc_gets_no_note
test_the_owner_reader_is_message_material_only

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
