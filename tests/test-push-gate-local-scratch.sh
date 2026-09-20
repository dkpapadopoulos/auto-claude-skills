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

# ---------------------------------------------------------------------------
# ATTACK CELLS. Every one of these CERTIFIED — i.e. skipped the whole push gate
# — against the first version of this predicate, and the first three push the
# REAL repository when executed. They are pinned at the predicate level because
# that is where the decision is made, and each names the mechanism rather than
# the symptom.
#
# Run through `/bin/bash -c` deliberately. This repo's own record is that the
# agent shell is zsh, where `set -- $1` does not word-split a scalar, so every
# one of these predicates returns a different answer there. The first run of
# these probes was made in that shell and reported "no bypass" for all ten —
# including the baseline, which is the only reason it was caught.
# ---------------------------------------------------------------------------
_certifies() { # 0 when the predicate certifies (gate would be skipped)
    /bin/bash -c '. "$1"/hooks/lib/git-command.sh; command_push_is_local_scratch "$2"' _ "${PROJECT_ROOT}" "$1"
}

_attack() { # _attack <label> <command>
    rm -rf "${SCRATCH}"
    if _certifies "$2"; then
        _record_fail "attack refused: $1" "the predicate CERTIFIED this command — the whole push gate would be skipped"
    else
        _record_pass "attack refused: $1"
    fi
}

test_baseline_still_certifies_at_predicate_level() {
    # The control for every attack cell below. Without it a predicate that
    # refused everything would score a perfect attack sheet.
    rm -rf "${SCRATCH}"
    if _certifies "${_SCRATCH_PUSH}"; then
        _record_pass "baseline scratch command still certifies (attack controls are live)"
    else
        _record_fail "baseline scratch command still certifies" \
            "the predicate refuses even the intended case — every attack cell below passes vacuously"
    fi
}

test_attack_env_prefix_redirects_git() {
    # GIT_DIR/GIT_WORK_TREE are skipped by _gc_segment_git_sub (correct for
    # DETECTION, fatal for certification): the segment reads as a push in the
    # scratch dir while git acts on the real repository.
    _attack "GIT_DIR= env prefix on the push" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && GIT_DIR=${PROJECT_ROOT}/.git git push origin main"
    _attack "GIT_WORK_TREE= env prefix on the push" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && GIT_WORK_TREE=${PROJECT_ROOT} git push origin main"
}

test_attack_separate_git_dir() {
    # Wires the scratch worktree to a real repository's gitdir. The option's
    # VALUE was being skipped, so the reported target was the scratch dir.
    _attack "git init --separate-git-dir <real>/.git" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q --separate-git-dir ${PROJECT_ROOT}/.git . && git commit -m x && git push origin main"
}

test_attack_untrackable_cd() {
    # Bare `cd` goes to $HOME and `cd -` to the previous directory; neither
    # yields a target, so both fell through to the inert whitelist (which
    # vouches for `cd`) leaving the tracked cwd stale while the real one moved.
    _attack "bare cd (real cwd becomes \$HOME)" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && cd && git init -q . && git commit -m x && git push origin main"
    _attack "cd - (tracked cwd goes stale)" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && cd - && git init -q . && git commit -m x && git push origin main"
    # A relative target was appended textually, so `..` was never resolved:
    # tracked cwd read <scratch>/../.. while the shell was at /.
    _attack "cd ../.. escape" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && cd ../.. && git init -q . && git commit -m x && git push origin main"
}

test_attack_push_before_init() {
    # Ordering was never enforced, so a push was excused by an init that had
    # not happened yet.
    _attack "push ordered before the init" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git push origin main && git init -q . && git commit -m x"
}

test_attack_failed_cd_carries_on() {
    # THE one a reviewer found and I did not. `_gc_split_segments` discards the
    # operator, so `A ; B` and `A && B` are identical to every predicate built
    # on it — and they are not identical at runtime. With `;` a FAILED `cd`
    # does not stop the command: the shell stays in the session's own checkout,
    # `git init` REINITIALISES the real repository, and the commit reaches the
    # real remote. Executed end to end by the reviewer against a fixture with a
    # remote, the commit landed on it.
    #
    # It is the reinit bypass arriving from the other side: the directory that
    # does not exist is never entered, so the "target must not exist" condition
    # is satisfied by a path nothing ever touches. And it is not exotic — it is
    # the reported #231 command with `;` separators, which an agent writes by
    # habit.
    _attack "failed cd carried on by ';' separators" \
        "cd /tmp/acs-231-absent-$$ ; git init ; git commit --allow-empty -m X ; git push origin main"
    _attack "failed cd carried on by newline separators" \
        "cd /tmp/acs-231-absent-$$
git init
git commit --allow-empty -m X
git push origin main"
    # THE cell that makes the `&&` requirement load-bearing. With a `mkdir`
    # present the mkdir condition is satisfied, so only the separator check can
    # refuse this: the mkdir itself FAILS (no parent), `;` carries execution on
    # regardless, the `cd` fails too, and `git init` reinitialises the session's
    # own repository. Without this cell, deleting the separator check failed
    # nothing — dead code implying coverage it did not provide.
    _attack "failing mkdir carried on by ';' separators" \
        "mkdir /nope/deep/acs231-$$ ; cd /nope/deep/acs231-$$ ; git init ; git commit --allow-empty -m X ; git push origin main"
    _attack "no mkdir: P's existence at exec time is unproven" \
        "cd /tmp/acs-231-absent-$$ && git init -q . && git commit -m x && git push origin main"
}

test_failed_cd_is_denied_by_the_real_guard() {
    # PAIRED WITH THE UNIT CELLS ABOVE, and not redundant with them. When a
    # bypass hides the subject, a predicate-level cell can refuse for the wrong
    # reason and still look green; only a guard-level assertion separates "we
    # measured the wrong thing" from "we did not gate at all". This exact
    # command was measured ALLOW against the real guard before the fix, with
    # the bare push control denying.
    _expect deny "failed cd with ';' separators (end to end)" \
        "cd /tmp/acs-231-absent-$$ ; git init ; git commit --allow-empty -m X ; git push origin main"
}

test_attack_per_command_config() {
    # `git -c` sets configuration for one command, including remote URLs and
    # `url.*.insteadOf` rewrites.
    _attack "git -c remote.origin.url=<url> on the push" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && git -c remote.origin.url=https://github.com/a/b push origin main"
    # THIS is the cell that makes the `-c` refusal load-bearing. The command
    # above is also caught by the URL-shape check, so deleting the `-c` refusal
    # failed nothing and the check was dead code that implied coverage it did
    # not provide — found by mutating it. `include.path` pulls in another
    # repository's config, remotes and all, and contains no `://` and no
    # `user@host:`, so the URL check cannot see it.
    _attack "git -c include.path=<real>/.git/config (no URL shape)" \
        "mkdir -p ${SCRATCH} && cd ${SCRATCH} && git init -q . && git commit -m x && git -c include.path=${PROJECT_ROOT}/.git/config push origin main"
}

test_preconditions
test_baseline_still_certifies_at_predicate_level
test_attack_env_prefix_redirects_git
test_attack_separate_git_dir
test_attack_untrackable_cd
test_attack_push_before_init
test_attack_per_command_config
test_attack_failed_cd_carries_on
test_failed_cd_is_denied_by_the_real_guard
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
