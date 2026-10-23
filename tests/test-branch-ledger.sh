#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-branch-ledger.sh ==="

LIB="${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
assert_file_exists "branch-ledger.sh exists" "${LIB}"
# shellcheck disable=SC1090
. "${LIB}"

# Isolate HOME so markers don't touch the real ~/.claude. Scratch dirs go under
# TMPDIR and are removed on exit (#372); they used to stay in /tmp for good.
# The trap names the scratch HOME by its own variable: HOME is restored below.
_BLHOME="$(mktemp -d "${TMPDIR:-/tmp}/bl-home-XXXXXX")" || exit 1
_OLDHOME="$HOME"; export HOME="${_BLHOME}"
RA=""; RB=""; _NONGIT=""
trap 'rm -rf "${_BLHOME}" "${RA}" "${RB}" "${_NONGIT}"' EXIT

# Build two throwaway git repos with the same branch name but different remotes
_mkrepo() { # $1=dir $2=remoteurl
  mkdir -p "$1"; ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin "$2" && git checkout -q -b feature/x \
    && echo hi > f && git add -A && git commit -qm init ); }
RA="$(mktemp -d "${TMPDIR:-/tmp}/bl-a-XXXXXX")"; RB="$(mktemp -d "${TMPDIR:-/tmp}/bl-b-XXXXXX")"
_mkrepo "$RA" "git@example.com:org/repo-a.git"
_mkrepo "$RB" "git@example.com:org/repo-b.git"

# record in A, assert has/sha in A, absent in B (key isolation by repo)
( cd "$RA" && branch_ledger_record requesting-code-review )
( cd "$RA" && branch_ledger_has requesting-code-review ) && _r=0 || _r=1
assert_equals "A has milestone after record" "0" "$_r"
( cd "$RB" && branch_ledger_has requesting-code-review ) && _r=0 || _r=1
assert_equals "B (same branch name, diff repo) does NOT inherit" "1" "$_r"

# recorded sha matches A's HEAD
_a_head="$(cd "$RA" && git rev-parse HEAD)"
assert_equals "recorded sha == A HEAD" "$_a_head" "$(cd "$RA" && branch_ledger_sha requesting-code-review)"

# detached HEAD is its own boundary (different key than the branch)
( cd "$RA" && git checkout -q --detach HEAD && branch_ledger_has requesting-code-review ) && _r=0 || _r=1
assert_equals "detached HEAD does not see branch marker" "1" "$_r"

# non-git dir → key undeterminable → record is a no-op, has returns 1, never errors
_NONGIT="$(mktemp -d "${TMPDIR:-/tmp}/bl-nogit-XXXXXX")"
( cd "$_NONGIT" && branch_ledger_record verification-before-completion ); _rc=$?
assert_equals "record in non-git exits 0 (fail-open)" "0" "$_rc"
( cd "$_NONGIT" && branch_ledger_has verification-before-completion ) && _r=0 || _r=1
assert_equals "non-git has() returns 1" "1" "$_r"

export HOME="$_OLDHOME"
print_summary
exit $?
