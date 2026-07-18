#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-verdict-lib.sh ==="

# ---- Content assertion: project-verification artifact documents the sha field ----
SKILL="${PROJECT_ROOT}/skills/project-verification/SKILL.md"
s="$(cat "${SKILL}")"
assert_contains "artifact snippet computes HEAD sha" "git rev-parse HEAD" "${s}"
assert_contains "artifact schema documents sha field" '"sha"' "${s}"

# ---- Unit tests for hooks/lib/verdict.sh ----
LIB="${PROJECT_ROOT}/hooks/lib/verdict.sh"
assert_file_exists "verdict.sh exists" "${LIB}"
# shellcheck disable=SC1090
. "${LIB}"

_bool() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }

TMP="$(mktemp -d /tmp/verdict-XXXXXX)"
_OLDHOME="$HOME"
REPO="${TMP}/repo"
mkdir -p "${REPO}"
(
  cd "${REPO}"
  git init -q
  git config user.email t@t; git config user.name t
  mkdir -p config; echo '{}' > config/default-triggers.json
  git add -A; git commit -qm c1
)
C1="$(git -C "${REPO}" rev-parse HEAD)"

export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
TOKEN="tok1"
ART="${HOME}/.claude/.skill-project-verified-${TOKEN}"
mkart() { printf '%s' "$1" > "${ART}"; }

# clean verdict at C1
mkart "$(jq -nc --arg s "${C1}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "clean verdict detected"        "0" "$(_bool verdict_is_clean "${TOKEN}")"
assert_equals "sha_is_head at C1"             "0" "$(_bool verdict_sha_is_head "${TOKEN}" "${REPO}")"
assert_equals "covers_head at C1"             "0" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"
assert_equals "clean => no test failure"      "1" "$(_bool verdict_has_test_failure "${TOKEN}")"
assert_equals "routing repo detected"         "0" "$(_bool is_routing_repo "${REPO}")"

# failing verdict at C1
mkart "$(jq -nc --arg s "${C1}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "test failure detected"         "0" "$(_bool verdict_has_test_failure "${TOKEN}")"
assert_equals "failing gate named"        "tests" "$(verdict_failing_gates "${TOKEN}")"
assert_equals "failing => not clean"          "1" "$(_bool verdict_is_clean "${TOKEN}")"

# ancestor sha: add C2, artifact still references C1
( cd "${REPO}"; echo x >> config/default-triggers.json; git commit -qam c2 )
mkart "$(jq -nc --arg s "${C1}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "ancestor covers_head"          "0" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"
assert_equals "ancestor is not head"          "1" "$(_bool verdict_sha_is_head "${TOKEN}" "${REPO}")"

# unrelated sha (cross-branch) MUST NOT cover HEAD -- false-block guard
mkart "$(jq -nc '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}')"
assert_equals "unrelated sha !covers (false-block guard)" "1" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"

# no-sha artifact MUST NOT cover HEAD
mkart "$(jq -nc '{failed:[],could_not_verify:[],gate_gaming_status:"clean"}')"
assert_equals "missing sha !covers"           "1" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"

# absent artifact
rm -f "${ART}"
assert_equals "absent => not clean"           "1" "$(_bool verdict_is_clean "${TOKEN}")"
assert_equals "absent => no failure"          "1" "$(_bool verdict_has_test_failure "${TOKEN}")"
assert_equals "absent => no cover"            "1" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"

# non-routing repo (no config/default-triggers.json)
REPO2="${TMP}/repo2"; mkdir -p "${REPO2}"
( cd "${REPO2}"; git init -q; git config user.email t@t; git config user.name t; echo hi > f; git add -A; git commit -qm c )
assert_equals "non-routing repo not detected" "1" "$(_bool is_routing_repo "${REPO2}")"

# diff_touches_routing: routing change vs base
( cd "${REPO}"
  git checkout -q -b feature
  git branch -q main C1 2>/dev/null || git branch -q -f main "${C1}"
  mkdir -p hooks; echo 'echo hi' > hooks/x.sh
  git add -A; git commit -qm routing-change )
assert_equals "diff touches routing (hooks/)" "0" "$(_bool diff_touches_routing "${REPO}")"

# verdict_routing_delta: routing files changed AFTER the verdict's sha => 0 (delta)
FHEAD="$(git -C "${REPO}" rev-parse HEAD)"
mkart "$(jq -nc --arg s "${C1}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "routing delta since old sha" "0" "$(_bool verdict_routing_delta "${TOKEN}" "${REPO}")"
# verdict at HEAD => no routing delta since => 1
mkart "$(jq -nc --arg s "${FHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "no routing delta at HEAD" "1" "$(_bool verdict_routing_delta "${TOKEN}" "${REPO}")"

# ---- verdict_resolve_token: bind verdict to COMMIT (sha), not session token ----
# A payload-less SKILL writes the verdict under the shared singleton's token while
# the guard resolves payload-first (issue #51); concurrent sessions clobber the
# singleton so the tokens diverge and the gate would never find the verdict.
# Resolution keeps the session token whenever ITS artifact covers HEAD (byte-identical
# to prior behavior) and only otherwise consults sibling artifacts bound to the same HEAD.
rm -f "${HOME}/.claude/.skill-project-verified-"*
RHEAD="$(git -C "${REPO}" rev-parse HEAD)"
mkart_tok() { printf '%s' "$2" > "${HOME}/.claude/.skill-project-verified-$1"; }

# (a) session token's own verdict covers HEAD -> returned verbatim (no sibling scan)
mkart_tok "session-self" "$(jq -nc --arg s "${RHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
mkart_tok "session-sib"  "$(jq -nc --arg s "${RHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "resolve: own covering token wins" "session-self" "$(verdict_resolve_token "session-self" "${REPO}")"

# (b) session token absent, a SIBLING verdict covers HEAD -> sibling bridges the deadlock
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart_tok "session-sib" "$(jq -nc --arg s "${RHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "resolve: sibling covering verdict bridges deadlock" "session-sib" "$(verdict_resolve_token "session-absent" "${REPO}")"

# (c) deny-bias: a sibling FAILED@HEAD outranks a sibling CLEAN@HEAD
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart_tok "session-clean"  "$(jq -nc --arg s "${RHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
mkart_tok "session-failed" "$(jq -nc --arg s "${RHEAD}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
RT="$(verdict_resolve_token "session-absent" "${REPO}")"
assert_equals "resolve: failed@HEAD sibling wins (deny-bias)" "0" "$(_bool verdict_has_test_failure "${RT}")"

# (d) nothing covers HEAD anywhere -> session token returned UNCHANGED (absent semantics kept)
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart_tok "session-stale" "$(jq -nc '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}')"
assert_equals "resolve: no covering verdict => session token unchanged" "session-absent" "$(verdict_resolve_token "session-absent" "${REPO}")"

# (e) cross-token bridging is EXACT-HEAD only: a FOREIGN clean verdict at an ANCESTOR
# must NOT bridge (ancestor acceptance is scoped to the session's OWN token, step 1).
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart_tok "session-anc" "$(jq -nc --arg s "${C1}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "resolve: foreign ancestor-clean does NOT bridge (exact-HEAD only)" "session-absent" "$(verdict_resolve_token "session-absent" "${REPO}")"
# but the SAME artifact under the session's OWN token DOES cover (ancestor, step 1)
mv "${HOME}/.claude/.skill-project-verified-session-anc" "${HOME}/.claude/.skill-project-verified-session-own"
assert_equals "resolve: own ancestor-clean still covers (step 1)" "session-own" "$(verdict_resolve_token "session-own" "${REPO}")"

# (f) issue #123: own ANCESTOR-clean must NOT shadow a sibling EXACT-HEAD clean.
# The stronger evidence (exact HEAD) outranks the weaker (own ancestor) across tokens —
# routing-governance needs a verdict AT HEAD, so an own-ancestor short-circuit that hides
# a genuine sibling exact-HEAD verdict is a false-block.
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart_tok "session-own" "$(jq -nc --arg s "${C1}"    '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
mkart_tok "session-sib" "$(jq -nc --arg s "${RHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "resolve: sibling exact-HEAD outranks own ancestor-clean (#123)" "session-sib" "$(verdict_resolve_token "session-own" "${REPO}")"

# (g) deny-bias preserved across the widened bridge: own ancestor-clean + sibling
# exact-HEAD FAILED => the sibling failure wins (a failure at HEAD outranks a clean ancestor).
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart_tok "session-own" "$(jq -nc --arg s "${C1}"    '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
mkart_tok "session-sib" "$(jq -nc --arg s "${RHEAD}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
RT3="$(verdict_resolve_token "session-own" "${REPO}")"
assert_equals "resolve: own ancestor yields to sibling FAILED@HEAD (deny-bias, #123)" "session-sib" "${RT3}"
assert_equals "resolve: the resolved token carries the failure" "0" "$(_bool verdict_has_test_failure "${RT3}")"

# (h) #123 regression guard: own EXACT-HEAD clean is still preferred over a sibling
# EXACT-HEAD clean (own fast path preserved — byte-identical to case (a)).
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart_tok "session-own" "$(jq -nc --arg s "${RHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
mkart_tok "session-sib" "$(jq -nc --arg s "${RHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
assert_equals "resolve: own exact-HEAD clean still wins over sibling exact-HEAD clean" "session-own" "$(verdict_resolve_token "session-own" "${REPO}")"

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
exit $?
