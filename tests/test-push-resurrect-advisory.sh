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
# The developer's own git config (a global remote.pushDefault, push.default or
# insteadOf) must not change what a cell measures.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
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
    # From another worktree of the same repository: the directory the command
    # names is accepted only when it shares the session's --git-common-dir.
    local d ctx
    d="$(_fixture dashc)"
    _g -C "${d}/remote.git" branch -q -D feat
    _g -C "${d}/work" worktree add -q "${d}/wt" main 2>/dev/null
    ctx="$(_ctx "$(_run "${d}/wt" "git -C ${d}/work push origin feat")")"
    assert_contains "git -C <dir> push is checked in <dir>" "origin/feat" "${ctx}"
}

test_foreign_repo_config_is_never_run() {
    # SECURITY. git runs programs a repository's own config names (here
    # remote.origin.uploadpack), and this hook runs BEFORE the user approves the
    # command. A directory the command names is used only when it is a worktree
    # of the session's own repository, the rule openspec-guard.sh applies (#219).
    # Control: from inside that repository the same program does run, so the
    # harness can see an executed config program.
    local d other marker c out
    d="$(_fixture foreign)"
    _g -C "${d}/remote.git" branch -q -D feat
    marker="${d}/uploadpack-ran"
    printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "${marker}" > "${d}/up.sh"
    chmod +x "${d}/up.sh"
    _g -C "${d}/work" config remote.origin.uploadpack "${d}/up.sh"
    other="${T}/other-session"
    _g init -q "${other}"
    for c in "git -C ${d}/work push origin feat" "cd ${d}/work && git push origin feat"; do
        out="$(_run "${other}" "${c}")"
        assert_equals "a push naming another repository: no output (${c%% *} form)" "" "${out}"
    done
    if [ -e "${marker}" ]; then
        _record_fail "a push naming another repository never runs that repository's config programs" \
            "remote.origin.uploadpack ran"
    else
        _record_pass "a push naming another repository never runs that repository's config programs"
    fi
    _run "${d}/work" "git push origin feat" >/dev/null
    if [ -e "${marker}" ]; then
        _record_pass "from inside the repository its uploadpack does run (control)"
    else
        _record_fail "from inside the repository its uploadpack does run (control)" \
            "never ran — the cell above cannot tell a refused directory from a never-run program"
    fi
}

test_quoted_words_are_unquoted() {
    # git-command.sh strips one layer of quotes from a refspec; the walk here
    # must too, or a quoted form looks up branch."feat" and says nothing.
    local d c
    d="$(_fixture quoted)"
    _g -C "${d}/remote.git" branch -q -D feat
    for c in 'git push origin "feat"' "git push origin 'feat'" 'git push "origin" feat'; do
        assert_contains "quoted form is checked: ${c}" "origin/feat" "$(_ctx "$(_run "${d}/work" "${c}")")"
    done
}

test_remote_wait_is_capped_below_the_hook_timeout() {
    # hooks.json gives this hook 10 s. A larger ACS_PUSH_REMOTE_TIMEOUT would let
    # the harness kill it mid-wait, which drops the advisory silently.
    local d pidf ctx
    d="$(_fixture cap)"
    pidf="${d}/ssh.pid"
    printf '#!/bin/sh\necho $$ > "%s"\nexec sleep 30\n' "${pidf}" > "${d}/slow-ssh"
    chmod +x "${d}/slow-ssh"
    _g -C "${d}/work" config core.sshCommand "${d}/slow-ssh"
    _g -C "${d}/work" remote set-url origin "ssh://example.invalid/x.git"
    ctx="$(_ctx "$(ACS_PUSH_REMOTE_TIMEOUT=60 _run "${d}/work" "git push origin feat")")"
    [ -s "${pidf}" ] && kill "$(cat "${pidf}")" 2>/dev/null
    assert_contains "ACS_PUSH_REMOTE_TIMEOUT above 8 is capped at 8 s" "within 8 s" "${ctx}"
}

# _ssh_alive_after_timeout <dir> <sshCommand> -> "alive" or "gone": whether the
# ssh git started is still running once the hook has given up on it.
_ssh_alive_after_timeout() {
    local d="$1" pidf="$1/ssh.pid" pid i=0
    _g -C "${d}/work" config core.sshCommand "$2"
    _g -C "${d}/work" remote set-url origin "ssh://example.invalid/x.git"
    ACS_PUSH_REMOTE_TIMEOUT=1 _run "${d}/work" "git push origin feat" > /dev/null
    pid="$(cat "${pidf}" 2>/dev/null)"
    [ -n "${pid}" ] || { printf 'no-ssh'; return; }
    while kill -0 "${pid}" 2>/dev/null && [ "${i}" -lt 10 ]; do sleep 0.1; i=$(( i + 1 )); done
    if kill -0 "${pid}" 2>/dev/null; then printf 'alive'; kill "${pid}" 2>/dev/null; else printf 'gone'; fi
}

test_timeout_leaves_no_ssh_behind() {
    # On a timeout the hook killed git, but git's ssh child kept running,
    # reparented, for as long as the remote took to answer. The whole tree must
    # go. `stub; true` is a command the shell git starts cannot exec in place,
    # so the stub is a level deeper: git, sh, stub. (A plain `stub -o x` is
    # exec'd by that sh and is git's child again.)
    local d
    d="$(_fixture orphan)"
    printf '#!/bin/sh\necho $$ > "%s"\nexec /bin/sleep 30\n' "${d}/ssh.pid" > "${d}/slow-ssh"
    chmod +x "${d}/slow-ssh"
    assert_equals "timeout: the ssh git ran is killed with it" "gone" \
        "$(_ssh_alive_after_timeout "${d}" "${d}/slow-ssh")"
    rm -f "${d}/ssh.pid"
    assert_equals "timeout: an ssh behind a shell core.sshCommand needs is killed too" "gone" \
        "$(_ssh_alive_after_timeout "${d}" "${d}/slow-ssh; true")"
}

test_wait_is_bounded_by_the_clock() {
    # The wait counted polls, not seconds, so anything that slowed each poll
    # (a loaded machine) stretched it past the hook's 10 s timeout and the
    # advisory was lost. Here every `sleep` the hook runs takes half a second,
    # so 25 polls at the default 5 s would take 12.5 s.
    local d t0 took ctx
    d="$(_fixture clock)"
    mkdir -p "${d}/slowbin"
    printf '#!/bin/sh\nexec /bin/sleep 0.5\n' > "${d}/slowbin/sleep"
    printf '#!/bin/sh\necho $$ > "%s"\nexec /bin/sleep 30\n' "${d}/ssh.pid" > "${d}/slow-ssh"
    chmod +x "${d}/slowbin/sleep" "${d}/slow-ssh"
    _g -C "${d}/work" config core.sshCommand "${d}/slow-ssh"
    _g -C "${d}/work" remote set-url origin "ssh://example.invalid/x.git"
    t0="${SECONDS}"
    ctx="$(_ctx "$(PATH="${d}/slowbin:${PATH}" _run "${d}/work" "git push origin feat")")"
    took=$(( SECONDS - t0 ))
    [ -s "${d}/ssh.pid" ] && kill "$(cat "${d}/ssh.pid")" 2>/dev/null
    assert_contains "slow polls: still reports could not check" "could not check" "${ctx}"
    if [ "${took}" -lt 10 ]; then
        _record_pass "slow polls: the hook returns inside its 10 s timeout"
    else
        _record_fail "slow polls: the hook returns inside its 10 s timeout" "took ${took} s"
    fi
}

test_detached_head_bare_push() {
    local d out
    d="$(_fixture detached)"
    _g -C "${d}/remote.git" branch -q -D feat
    _g -C "${d}/work" switch -q --detach HEAD
    out="$(_run "${d}/work" "git push")"
    assert_equals "detached HEAD bare push: no output" "" "${out}"
}

# --- The remote and destination are the ones the COMMAND names (review I1) ---

# _add_fork <dir> — a second bare remote `fork` that holds `feat`
_add_fork() {
    _g init -q --bare "$1/fork.git"
    _g -C "$1/work" remote add fork "$1/fork.git"
    _g -C "$1/work" push -q fork feat 2>/dev/null
}

test_push_to_other_remote_is_not_blamed_on_upstream() {
    local d out
    d="$(_fixture otherremote)"
    _add_fork "${d}"
    _g -C "${d}/remote.git" branch -q -D feat
    out="$(_run "${d}/work" "git push fork feat")"
    assert_equals "push to a remote that has the branch: no output" "" "${out}"
}

test_renamed_destination_is_not_the_source() {
    local d out
    d="$(_fixture renamed)"
    _g -C "${d}/remote.git" branch -q -D feat
    out="$(_run "${d}/work" "git push origin feat:other")"
    assert_equals "src:dst push to a new name: no output" "" "${out}"
}

test_head_colon_dst_checks_dst() {
    local d ctx
    d="$(_fixture headdst)"
    _g -C "${d}/remote.git" branch -q -D feat
    _g -C "${d}/work" switch -q -c wip
    ctx="$(_ctx "$(_run "${d}/work" "git push origin HEAD:feat")")"
    assert_contains "HEAD:feat is checked as feat" "origin/feat" "${ctx}"
}

test_named_remote_overrides_upstream_remote() {
    # feat tracks fork, which deleted it; the command pushes to origin, which
    # still has it.
    local d out
    d="$(_fixture namedremote)"
    _add_fork "${d}"
    _g -C "${d}/work" branch -q --set-upstream-to=fork/feat feat
    _g -C "${d}/fork.git" branch -q -D feat
    out="$(_run "${d}/work" "git push origin feat")"
    assert_equals "named remote still has the branch: no output" "" "${out}"
}

test_bare_push_follows_push_remote() {
    local d out
    d="$(_fixture pushremote)"
    _add_fork "${d}"
    _g -C "${d}/work" config branch.feat.pushRemote fork
    _g -C "${d}/remote.git" branch -q -D feat
    out="$(_run "${d}/work" "git push")"
    assert_equals "bare push goes to pushRemote, which has the branch: no output" "" "${out}"
}

test_repo_flag_names_the_remote() {
    local d out
    d="$(_fixture repoflag)"
    _add_fork "${d}"
    _g -C "${d}/remote.git" branch -q -D feat
    out="$(_run "${d}/work" "git push --repo=fork")"
    assert_equals "--repo=fork, which has the branch: no output" "" "${out}"
}

# --- The user's own ssh configuration is used (review I2) ---
test_core_ssh_command_is_respected() {
    local d marker
    d="$(_fixture sshcmd)"
    marker="${d}/ssh-was-called"
    printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "${marker}" > "${d}/fake-ssh"
    chmod +x "${d}/fake-ssh"
    _g -C "${d}/work" config core.sshCommand "${d}/fake-ssh"
    _g -C "${d}/work" remote set-url origin "ssh://example.invalid/x.git"
    ( unset GIT_SSH_COMMAND GIT_SSH; _run "${d}/work" "git push origin feat" >/dev/null )
    if [ -e "${marker}" ]; then
        _record_pass "the remote query uses the repo's core.sshCommand"
    else
        _record_fail "the remote query uses the repo's core.sshCommand" "core.sshCommand was never run"
    fi
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
test_foreign_repo_config_is_never_run
test_quoted_words_are_unquoted
test_remote_wait_is_capped_below_the_hook_timeout
test_timeout_leaves_no_ssh_behind
test_wait_is_bounded_by_the_clock
test_detached_head_bare_push
test_push_to_other_remote_is_not_blamed_on_upstream
test_renamed_destination_is_not_the_source
test_head_colon_dst_checks_dst
test_named_remote_overrides_upstream_remote
test_bare_push_follows_push_remote
test_repo_flag_names_the_remote
test_core_ssh_command_is_respected
test_fail_open_on_garbage

assert_test_functions_wired "${BASH_SOURCE[0]}"
print_summary
