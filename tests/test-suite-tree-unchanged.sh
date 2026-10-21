#!/usr/bin/env bash
# tests/test-suite-tree-unchanged.sh — #367
#
# A full run of the suite left config/fallback-registry.json modified on a green
# run (measured 2026-09-29 and again 2026-10-20: one byte, the trailing newline).
# The cause was a test that saved the file through `$(cat)` and restored it with
# `printf '%s'`. Nothing reported it: a suite that changes tracked files read as
# a clean pass, and the change waited to be swept into the next `git add -A`.
#
# tests/run-tests.sh now takes the tracked tree's state before and after every
# test file and fails the file after which it differs. These cells drive a COPY
# of the real runner (never a hand-written one) inside throwaway git repos.
#
# The state is content, not only `git status`: a file that was already modified
# when the run started and is changed again keeps the same status line, so a
# status-only check would miss exactly the dirty-tree case a verification run
# before committing produces.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

RUNNER="${SCRIPT_DIR}/run-tests.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/acs-tree-unchanged.XXXXXX")"
trap 'rm -rf "${W}"' EXIT

_g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# _repo <name> — a git repo with a tracked config/data.json (ending in a
# newline) and a copy of the real runner under tests/.
_repo() {
    local d="${W}/$1"
    mkdir -p "${d}/tests" "${d}/config"
    printf '{"a": 1}\n' > "${d}/config/data.json"
    cp "${RUNNER}" "${d}/tests/run-tests.sh"
    _g init -q "${d}"
    _g -C "${d}" add -A
    _g -C "${d}" commit -q -m init
    printf '%s' "${d}"
}

# _test <repo> <name> <body> — writes tests/test-<name>.sh
_test() {
    printf '#!/usr/bin/env bash\nD="$(cd "$(dirname "$0")/.." && pwd)"\n%s\nexit 0\n' "$3" \
        > "$1/tests/test-$2.sh"
}

_run() { bash "$1/tests/run-tests.sh" > "$1/run.log" 2>&1; echo "$?"; }
_sentinel() { tail -1 "$1/run.log"; }

# --- the defect, reproduced exactly: save via $(cat), restore via printf '%s'
D="$(_repo strip)"
_test "${D}" "a-strips" 'o="$(cat "$D/config/data.json")"; printf "%s" "$o" > "$D/config/data.json"'
_test "${D}" "b-clean" ':'
rc="$(_run "${D}")"
assert_equals "a test that strips a tracked file's newline fails the run" "1" "${rc}"
assert_contains "the sentinel reports one failed file" "files=2 passed=1 failed=1 status=fail" "$(_sentinel "${D}")"
assert_contains "the culprit is named" "test-a-strips.sh" "$(grep -F 'Failed:' "${D}/run.log")"
# The runner cannot tell a test's write from a concurrent edit (another session,
# an IDE save), so the message must not claim the test did it.
assert_contains "the message says the tree changed WHILE the file ran" \
    "the tracked tree changed while test-a-strips.sh ran" "$(cat "${D}/run.log")"
assert_contains "the message names the other possible cause" "concurrent edit" "$(cat "${D}/run.log")"
assert_contains "the changed path is named" "config/data.json" "$(cat "${D}/run.log")"
assert_not_contains "the next, clean file is not blamed" "test-b-clean.sh" "$(grep -F 'Failed:' "${D}/run.log")"

# --- control: a test that changes the file and restores it byte for byte
D="$(_repo restore)"
_test "${D}" "a-restores" 'cp "$D/config/data.json" "$D/bak"; printf "x" >> "$D/config/data.json"; cp "$D/bak" "$D/config/data.json"; rm -f "$D/bak"'
rc="$(_run "${D}")"
assert_equals "a byte-exact restore passes" "0" "${rc}"
assert_contains "byte-exact restore: sentinel says pass" "status=pass" "$(_sentinel "${D}")"

# --- control: untracked files are not the tracked tree
D="$(_repo untracked)"
_test "${D}" "a-untracked" 'printf "x" > "$D/scratch.txt"'
rc="$(_run "${D}")"
assert_equals "creating an untracked file passes" "0" "${rc}"

# --- an already-modified file changed again: status line identical, content not
D="$(_repo dirty)"
printf '{"a": 2}\n' > "${D}/config/data.json"
_test "${D}" "a-rewrites" 'printf "{\"a\": 3}\n" > "$D/config/data.json"'
rc="$(_run "${D}")"
assert_equals "changing an already-modified tracked file fails the run" "1" "${rc}"

# --- an already-modified file reverted: its status line disappears, and the
# message must still name it (the first cut printed only lines that appeared)
D="$(_repo revert)"
printf '{"a": 2}\n' > "${D}/config/data.json"
_test "${D}" "a-reverts" 'git -C "$D" checkout -q -- config/data.json'
rc="$(_run "${D}")"
assert_equals "reverting an already-modified tracked file fails the run" "1" "${rc}"
assert_contains "the reverted path is named in the runner's message" "config/data.json" \
    "$(sed -n '/the tracked tree changed while/,/^---/p' "${D}/run.log")"

# --- a dirty tree the tests leave alone passes
D="$(_repo dirtyok)"
printf '{"a": 2}\n' > "${D}/config/data.json"
_test "${D}" "a-noop" ':'
rc="$(_run "${D}")"
assert_equals "a tree dirty before the run and untouched by it passes" "0" "${rc}"

# --- staging counts: the index is part of the tracked tree
D="$(_repo staged)"
_test "${D}" "a-stages" 'printf "x\n" >> "$D/config/data.json"; git -C "$D" add config/data.json; git -C "$D" checkout -q -- config/data.json'
rc="$(_run "${D}")"
assert_equals "a test that leaves a change staged fails the run" "1" "${rc}"

# --- HEAD is part of the state: a commit with no content change still moves it
D="$(_repo commits)"
_test "${D}" "a-commits" 'git -C "$D" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x'
rc="$(_run "${D}")"
assert_equals "a test that commits (even an empty commit) fails the run" "1" "${rc}"

# --- session-start regenerates config/fallback-registry.json whenever it is out
# of date with default-triggers.json, and many test files run it against the
# checkout, so after a routing edit the first of them rewrote the file and was
# blamed for it. The runner regenerates it once, before any snapshot, and says
# so. The stand-in hook below does what session-start's step 10c does: derive
# the file, unless _SKILL_TEST_MODE is set.
D="$(_repo regen)"
mkdir -p "${D}/hooks"
printf '{}\n' > "${D}/config/fallback-registry.json"
printf '#!/bin/bash\n[ -n "${_SKILL_TEST_MODE:-}" ] || cp "$CLAUDE_PLUGIN_ROOT/config/data.json" "$CLAUDE_PLUGIN_ROOT/config/fallback-registry.json"\nexit 0\n' \
    > "${D}/hooks/session-start-hook.sh"
_g -C "${D}" add hooks config
_g -C "${D}" commit -q -m hook
_test "${D}" "a-runs-hook" 'CLAUDE_PLUGIN_ROOT="$D" bash "$D/hooks/session-start-hook.sh" < /dev/null'
rc="$(_run "${D}")"
assert_equals "an out-of-date fallback that session-start regenerates blames no test file" "0" "${rc}"
assert_contains "the runner says it regenerated the fallback, which needs committing" \
    "config/fallback-registry.json" "$(grep -A2 -F 'NOTE' "${D}/run.log")"
_g -C "${D}" add config
_g -C "${D}" commit -q -m regenerated
rc="$(_run "${D}")"
assert_equals "an in-sync fallback passes" "0" "${rc}"
assert_not_contains "an in-sync fallback: no regeneration note" "fallback-registry" "$(cat "${D}/run.log")"
# The regeneration must not hide the original #367 defect in that same file.
_test "${D}" "b-strips-fallback" 'o="$(cat "$D/config/fallback-registry.json")"; printf "%s" "$o" > "$D/config/fallback-registry.json"'
rc="$(_run "${D}")"
assert_equals "a test that strips the fallback's newline still fails the run" "1" "${rc}"
assert_contains "and is the one named" "test-b-strips-fallback.sh" "$(grep -F 'Failed:' "${D}/run.log")"

# --- outside a git checkout the check says it could not run and does not fail
N="${W}/nogit"
mkdir -p "${N}/tests"
cp "${RUNNER}" "${N}/tests/run-tests.sh"
_test "${N}" "a-noop" ':'
rc="$(GIT_CEILING_DIRECTORIES="${W}" _run "${N}")"
assert_equals "no git checkout: the run still passes" "0" "${rc}"
assert_contains "no git checkout: says the tree check could not run" "cannot check" "$(cat "${N}/run.log")"
# Through the supported reader, not the sentinel literal: test-suite-completion.sh
# requires that no other test file spells the sentinel out.
bash "${SCRIPT_DIR}/../scripts/assert-suite-complete.sh" "${N}/run.log" >/dev/null 2>&1
assert_equals "no git checkout: the log still reads as complete and passing" "0" "$?"

print_summary
