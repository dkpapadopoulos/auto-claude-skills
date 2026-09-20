#!/usr/bin/env bash
# tests/test-push-gate-local-scratch.sh — #231 (scratch-repo half)
#
# A contributor building a local fixture repo to test push behaviour —
# `mkdir /tmp/x && cd /tmp/x && git init && git commit && git push origin main`
# — was denied by the gate they were testing. The push reaches no network:
# `origin` does not exist in a repo initialised moments earlier.
#
# MEASURED BEFORE THE FIX, and it decided the shape: narrowing only
# `mutate-then-push` (the leg that fired) changes nothing a contributor notices
# — the push falls through to the chain REVIEW gate and denies there instead,
# with or without a composition chain. So the skip covers the whole gate, which
# is a real widening, and every cell below that must KEEP denying is the price
# of it. Each allow cell is paired with a control that differs in one condition.
#
# The load-bearing condition is that the subject directory DOES NOT EXIST when
# the gate runs: `git init` inside an existing repository is a successful no-op,
# so without that check `cd <real repo> && git init && git commit -am x && git
# push origin main` would certify and ship real work unreviewed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
SCRATCH="/tmp/acs-231-fixture-$$"

_cleanup() { rm -rf "${SCRATCH}"; }
trap _cleanup EXIT

# _decide <chain|nochain> <command> -> prints deny|ALLOW
_decide() {
    local _mode="$1" _cmd="$2" _home _out
    _home="$(mktemp -d /tmp/acs231-home-XXXXXX)"
    mkdir -p "${_home}/.claude"
    : > "${_home}/t.jsonl"
    if [ "${_mode}" = "chain" ]; then
        printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
            > "${_home}/.claude/.skill-composition-state-session-t"
    fi
    rm -rf "${SCRATCH}"
    _out="$(jq -n --arg tp "${_home}/t.jsonl" --arg c "${_cmd}" \
              '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
            | HOME="${_home}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null)"
    rm -rf "${_home}"
    printf '%s' "${_out}" | jq -r '.hookSpecificOutput.permissionDecision // "ALLOW"' 2>/dev/null
}

_expect() { # _expect <deny|ALLOW> <label> <command>
    local _got _m
    for _m in chain nochain; do
        _got="$(_decide "${_m}" "$3")"
        if [ "${_got}" = "$1" ]; then
            _record_pass "[$_m] $2 -> $1"
        else
            _record_fail "[$_m] $2" "expected $1, got ${_got}"
        fi
    done
}

_SCRATCH_PUSH="mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -q --allow-empty -m x && git push origin main"

test_preconditions() {
    # Assert, do not arrange: without jq or the predicate every cell below is
    # vacuous, and a silently-vacuous gate test is worse than no test.
    if ! command -v jq >/dev/null 2>&1; then
        _record_fail "jq is available" "jq missing — every cell here would be vacuous"
        return
    fi
    if ! grep -q 'command_push_is_local_scratch' "${PROJECT_ROOT}/hooks/lib/git-command.sh"; then
        _record_fail "predicate exists in the lib" "command_push_is_local_scratch not found"
        return
    fi
    if [ -e "${SCRATCH}" ]; then
        _record_fail "fixture path is absent before each cell" "${SCRATCH} already exists"
        return
    fi
    _record_pass "preconditions hold (jq, predicate present, fixture path absent)"
}

test_scratch_push_is_allowed() {
    _expect ALLOW "the #231 scratch probe" "${_SCRATCH_PUSH}"
}

test_scratch_push_announces_the_skip() {
    # A skipped gate must SAY so (#198). Silence here is indistinguishable from
    # a gate that ran and passed.
    local _home _out _ctx
    _home="$(mktemp -d /tmp/acs231-home-XXXXXX)"; mkdir -p "${_home}/.claude"; : > "${_home}/t.jsonl"
    rm -rf "${SCRATCH}"
    _out="$(jq -n --arg tp "${_home}/t.jsonl" --arg c "${_SCRATCH_PUSH}" \
              '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
            | HOME="${_home}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null)"
    rm -rf "${_home}"
    _ctx="$(printf '%s' "${_out}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
    if printf '%s' "${_ctx}" | grep -q 'no jurisdiction'; then
        _record_pass "the skip is announced, not silent"
    else
        _record_fail "the skip is announced" "advisory did not state the skip: [${_ctx}]"
    fi
    # And it must NOT also claim the checks measured something — no check ran.
    if printf '%s' "${_ctx}" | grep -q 'the checks below measured'; then
        _record_fail "the skip advisory drops stale measurement notes" \
            "advisory still claims checks measured a subject: [${_ctx}]"
    else
        _record_pass "the skip advisory makes no claim about what was measured"
    fi
}

# --- controls: each differs from the allow cell in exactly one condition -----
test_reinit_in_a_real_repo_still_denies() {
    _expect deny "REINIT bypass (git init in an existing repo)" \
        "cd ${PROJECT_ROOT} && git init && git commit -am x && git push origin main"
}

test_existing_directory_still_denies() {
    _expect deny "subject directory already exists" \
        "cd /tmp && git init -q . && git commit -m x && git push origin main"
}

test_configured_remote_still_denies() {
    _expect deny "git remote add present" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git remote add origin git@github.com:a/b.git && git commit -m x && git push origin main"
}

test_url_remote_still_denies() {
    _expect deny "push names a URL" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && git push https://github.com/a/b.git main"
}

test_clone_still_denies() {
    _expect deny "git clone present (repo not created from nothing)" \
        "git clone https://github.com/a/b ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && git push origin main"
}

test_trailing_real_push_still_denies() {
    # The ALL-form: a qualifying push must not excuse a second, real one.
    _expect deny "scratch push followed by a real push" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && git push origin main && cd ${PROJECT_ROOT} && git push origin main"
}

test_command_substitution_still_denies() {
    _expect deny "command substitution smuggled into the arguments" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && git push origin main \$(git push origin main)"
}

test_unknown_segment_still_denies() {
    _expect deny "an unaccounted-for segment" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && ./deploy.sh && git push origin main"
}

test_ordinary_pushes_still_deny() {
    _expect deny "plain push" 'git push origin main'
    _expect deny "commit && push" 'git commit -m x && git push origin main'
}

test_preconditions
test_scratch_push_is_allowed
test_scratch_push_announces_the_skip
test_reinit_in_a_real_repo_still_denies
test_existing_directory_still_denies
test_configured_remote_still_denies
test_url_remote_still_denies
test_clone_still_denies
test_trailing_real_push_still_denies
test_command_substitution_still_denies
test_unknown_segment_still_denies
test_ordinary_pushes_still_deny

print_summary
