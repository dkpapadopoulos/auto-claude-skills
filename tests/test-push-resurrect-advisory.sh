#!/usr/bin/env bash
# tests/test-push-resurrect-advisory.sh — #368
#
# A squash or merge on GitHub auto-deletes the PR's head branch, and a later
# `git push` of the local branch RECREATES it — reported as `* [new branch]`,
# the only tell, and easy to read as routine. Observed three times (2026-08-29,
# 2026-10-03 twice). hooks/push-resurrect-advisory.sh warns BEFORE the push when
# the branch was on the remote before and is not there now.
#
# Every remote here is a LOCAL bare repository, so no cell touches the network.
# GitHub's auto-delete is simulated by deleting the branch inside the bare repo,
# which leaves the clone's upstream config and remote-tracking ref behind
# exactly as the real deletion does.
#
# THE NO-NETWORK CELLS HAVE A CONTROL. "No output" is equally true of a hook
# that asked the remote and found the branch, and of one that never asked. The
# first-push cell therefore points the remote at a path that does not exist;
# the unreachable-remote cell proves that path IS detected when the hook asks,
# so silence in the first-push cell means the hook did not ask.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

HOOK="${PROJECT_ROOT}/hooks/push-resurrect-advisory.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/acs-resurrect.XXXXXX")"
trap 'rm -rf "${T}"' EXIT

_g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }

# _fixture <name> -> builds ${T}/<name>/{remote.git,work}; `feat` is pushed with
# -u, so it has an upstream and a remote-tracking ref.
_fixture() {
    local d="${T}/$1"
    mkdir -p "${d}"
    _g init -q --bare "${d}/remote.git"
    _g init -q "${d}/work"
    _g -C "${d}/work" commit -q --allow-empty -m init
    _g -C "${d}/work" remote add origin "${d}/remote.git"
    _g -C "${d}/work" push -q -u origin main 2>/dev/null
    _g -C "${d}/work" switch -q -c feat
    _g -C "${d}/work" commit -q --allow-empty -m feat
    _g -C "${d}/work" push -q -u origin feat 2>/dev/null
    printf '%s' "${d}"
}

# _run <cwd> <command> -> the hook's stdout
_run() {
    local payload
    payload="$(jq -n --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')"
    ( cd "$1" && printf '%s' "${payload}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" 2>/dev/null )
}

_ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

# --- Cells -----------------------------------------------------------------

test_hook_exists() {
    if [ -x "${HOOK}" ] && /bin/bash -n "${HOOK}" 2>/dev/null; then
        _record_pass "hook exists, is executable and parses under /bin/bash"
    else
        _record_fail "hook exists, is executable and parses under /bin/bash" "${HOOK}"
    fi
}

test_registered_on_bash() {
    local n
    n="$(jq '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command
              | select(test("push-resurrect-advisory\\.sh$"))] | length' "${PROJECT_ROOT}/hooks/hooks.json" 2>/dev/null)"
    assert_equals "registered once as a PreToolUse Bash hook" "1" "${n}"
}

test_deleted_remote_with_tracking_ref() {
    local d out ctx
    d="$(_fixture deleted)"
    _g -C "${d}/remote.git" branch -q -D feat
    out="$(_run "${d}/work" "git push origin feat")"
    ctx="$(_ctx "${out}")"
    assert_contains "deleted remote branch: advisory names the branch" "origin/feat" "${ctx}"
    assert_contains "deleted remote branch: advisory says the push recreates it" "RECREATE" "${ctx}"
    assert_contains "deleted remote branch: advisory names the PR check" "gh pr view" "${ctx}"
    # The advisory never denies.
    assert_equals "advisory carries no permissionDecision" "" \
        "$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
    assert_equals "advisory is exactly one JSON object" "1" \
        "$(printf '%s' "${out}" | jq -s 'length' 2>/dev/null)"
}

test_deleted_remote_bare_push() {
    local d ctx
    d="$(_fixture bare)"
    _g -C "${d}/remote.git" branch -q -D feat
    ctx="$(_ctx "$(_run "${d}/work" "git push")")"
    assert_contains "bare git push of the current branch is checked too" "origin/feat" "${ctx}"
}

test_deleted_remote_after_prune() {
    # fetch --prune removes the remote-tracking ref; the upstream config stays,
    # and alone it is enough to say the branch was on the remote.
    local d ctx
    d="$(_fixture pruned)"
    _g -C "${d}/remote.git" branch -q -D feat
    _g -C "${d}/work" fetch -q --prune origin
    ctx="$(_ctx "$(_run "${d}/work" "git push origin feat")")"
    assert_contains "upstream config alone triggers the check" "origin/feat" "${ctx}"
}

test_tracking_ref_without_upstream() {
    # Pushed without -u by someone else and fetched: no upstream, but the
    # remote-tracking ref says the branch was there.
    local d ctx
    d="$(_fixture noupstream)"
    _g -C "${d}/work" branch -q --unset-upstream feat
    _g -C "${d}/remote.git" branch -q -D feat
    ctx="$(_ctx "$(_run "${d}/work" "git push origin feat")")"
    assert_contains "a remote-tracking ref alone triggers the check" "origin/feat" "${ctx}"
}

test_remote_branch_present() {
    local d out
    d="$(_fixture present)"
    out="$(_run "${d}/work" "git push origin feat")"
    assert_equals "remote branch still there: no output" "" "${out}"
}

test_unreachable_remote_is_announced() {
    local d ctx
    d="$(_fixture unreachable)"
    _g -C "${d}/work" remote set-url origin "${d}/nowhere.git"
    ctx="$(_ctx "$(_run "${d}/work" "git push origin feat")")"
    assert_contains "unreachable remote: says it could not check" "could not check" "${ctx}"
}

test_first_push_asks_nothing() {
    # A branch never seen on the remote. The remote is unreachable, so if the
    # hook asked it, the cell above shows it would have said so.
    local d out
    d="$(_fixture firstpush)"
    _g -C "${d}/work" switch -q -c fresh origin/main 2>/dev/null
    _g -C "${d}/work" commit -q --allow-empty -m fresh
    _g -C "${d}/work" remote set-url origin "${d}/nowhere.git"
    out="$(_run "${d}/work" "git push -u origin fresh")"
    assert_equals "first push of a never-pushed branch: no output, no remote query" "" "${out}"
}

test_deletion_push_is_ignored() {
    local d out
    d="$(_fixture deletion)"
    _g -C "${d}/remote.git" branch -q -D feat
    out="$(_run "${d}/work" "git push origin --delete feat")"
    assert_equals "a deletion push is not checked" "" "${out}"
}

test_non_push_commands() {
    local d
    d="$(_fixture nonpush)"
    _g -C "${d}/remote.git" branch -q -D feat
    assert_equals "git status: no output" "" "$(_run "${d}/work" "git status")"
    assert_equals "push inside a quoted string: no output" "" \
        "$(_run "${d}/work" "echo 'git push origin feat'")"
}

test_subject_dir_from_dash_c() {
    local d ctx
    d="$(_fixture dashc)"
    _g -C "${d}/remote.git" branch -q -D feat
    ctx="$(_ctx "$(_run "${T}" "git -C ${d}/work push origin feat")")"
    assert_contains "git -C <dir> push is checked in <dir>" "origin/feat" "${ctx}"
}

test_detached_head_bare_push() {
    local d out
    d="$(_fixture detached)"
    _g -C "${d}/remote.git" branch -q -D feat
    _g -C "${d}/work" switch -q --detach HEAD
    out="$(_run "${d}/work" "git push")"
    assert_equals "detached HEAD bare push: no output" "" "${out}"
}

test_fail_open_on_garbage() {
    local out rc
    out="$(printf 'not json' | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" 2>/dev/null)"; rc=$?
    assert_equals "garbage payload: exit 0" "0" "${rc}"
    assert_equals "garbage payload: no output" "" "${out}"
}

test_hook_exists
test_registered_on_bash
test_deleted_remote_with_tracking_ref
test_deleted_remote_bare_push
test_deleted_remote_after_prune
test_tracking_ref_without_upstream
test_remote_branch_present
test_unreachable_remote_is_announced
test_first_push_asks_nothing
test_deletion_push_is_ignored
test_non_push_commands
test_subject_dir_from_dash_c
test_detached_head_bare_push
test_fail_open_on_garbage

assert_test_functions_wired "${BASH_SOURCE[0]}"
print_summary
