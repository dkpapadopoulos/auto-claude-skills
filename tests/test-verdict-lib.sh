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

# A sha that is not a full object name MUST NOT cover HEAD (#428). Git resolves
# a ref-like string as a revision, so the word HEAD is "HEAD or an ancestor of
# it" for every commit. The ancestor cell above is the control that a real
# object name still covers.
for _bad in "HEAD" "HEAD~1" "master" "main" "@" "${C1:0:12}"; do
    mkart "$(jq -nc --arg s "${_bad}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
    assert_equals "non-sha '${_bad}' !covers"  "1" "$(_bool verdict_covers_head "${TOKEN}" "${REPO}")"
done

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

# ---- _routing_base: one base for both push spellings (#374) ----
# A repo made with `git init` + `remote add` has no origin/HEAD, which is the
# only state where the candidate order after it matters. _mk_base_repo <dir>
# <mainline-name>: mainline pushed, feat/x pushed with an upstream, then one
# unpushed commit on feat/x.
_mk_base_repo() {
    local d="$1" m="$2"
    mkdir -p "${d}/work"
    git init -q --bare "${d}/origin.git"
    ( cd "${d}/work"
      git init -q; git config user.email t@t; git config user.name t
      git checkout -q -b "${m}"
      mkdir -p hooks; echo base > hooks/a.sh; echo base > f
      git add -A; git commit -qm base
      git remote add origin "${d}/origin.git"
      git push -q origin "${m}"
      git checkout -q -b feat/x
      echo pushed > g; git add -A; git commit -qm pushed
      git push -q -u origin feat/x
      echo local > h; git add -A; git commit -qm unpushed ) >/dev/null 2>&1
}
BR="${TMP}/base-main"; _mk_base_repo "${BR}" main
BW="${BR}/work"
assert_equals "base repo has no origin/HEAD (precondition)" "1" "$(_bool git -C "${BW}" rev-parse --verify -q origin/HEAD)"
_b_head="$(_routing_base "${BW}" HEAD)"
_b_ref="$(_routing_base "${BW}" refs/heads/feat/x)"
assert_equals "B1 both spellings resolve one base" "${_b_head}" "${_b_ref}"
assert_equals "B2 that base is the mainline merge-base" "$(git -C "${BW}" merge-base feat/x main)" "${_b_head}"

# B3: no mainline name at all, so both spellings fall back to the branch's own upstream.
BT="${TMP}/base-trunk"; _mk_base_repo "${BT}" trunk
_t_up="$(git -C "${BT}/work" rev-parse origin/feat/x)"
assert_equals "B3 no mainline name: HEAD falls back to the upstream" "${_t_up}" "$(_routing_base "${BT}/work" HEAD)"
assert_equals "B3 no mainline name: refs/heads spelling does too"    "${_t_up}" "$(_routing_base "${BT}/work" refs/heads/feat/x)"

# B4: the invariant is the NET change against the mainline. A routing file
# changed and pushed, then restored to the mainline's content, is in the diff
# against the branch's remote copy and not in the net diff. Chosen, not an
# accident: this is what a clone with origin/HEAD set has always measured.
( cd "${BW}"
  echo changed > hooks/a.sh; git commit -qam change-routing; git push -q origin feat/x
  echo base > hooks/a.sh; git commit -qam restore-routing ) >/dev/null 2>&1
assert_not_contains "B4 a file restored to mainline content is not in the branch diff" "hooks/a.sh" "$(_branch_diff_names "${BW}" HEAD)"
assert_contains "B4 control: the branch's other change is in it" "g" "$(_branch_diff_names "${BW}" HEAD)"

# B5 red control: the pre-#374 candidate order, restored in a copy of the REAL
# lib, splits the two spellings. Without it B1 could pass on a repo where the
# order never mattered.
_OLD_LIB="${TMP}/verdict-old-order.sh"
sed -e 's|^    up="\${rev#refs/heads/}@{upstream}"$|    up="${rev}@{upstream}"|' \
    -e 's|^    for ref in origin/HEAD origin/main main origin/master master "\$up"; do$|    for ref in origin/HEAD "$up" origin/main main origin/master master; do|' \
    "${LIB}" > "${_OLD_LIB}"
assert_equals "B5 mutation applied (the copy differs from the lib)" "1" "$(_bool cmp -s "${LIB}" "${_OLD_LIB}")"
_o_head="$(/bin/bash -c '. "$1"; _routing_base "$2" HEAD' _ "${_OLD_LIB}" "${BW}")"
_o_ref="$(/bin/bash -c '. "$1"; _routing_base "$2" refs/heads/feat/x' _ "${_OLD_LIB}" "${BW}")"
assert_not_empty "B5 the old order still resolves a base for HEAD" "${_o_head}"
assert_equals "B5 the old order gives the two spellings different bases" "1" "$(_bool [ "${_o_head}" = "${_o_ref}" ])"

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
exit $?
