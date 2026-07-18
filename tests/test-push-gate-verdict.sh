#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-verdict.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# ---- Wiring assertions ----
g="$(cat "${GUARD}")"
assert_contains "gate sources verdict lib"          "verdict.sh"             "${g}"
assert_contains "gate does verify-hardening"        "verdict_has_test_failure" "${g}"
assert_contains "gate does routing governance"      "diff_touches_routing"   "${g}"

# ---- Behavioral setup (token resolves from transcript basename: t.jsonl -> session-t) ----
_OLDHOME="$HOME"
TMP="$(mktemp -d /tmp/pgv-XXXXXX)"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
_TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"
TOK="session-t"
ART="${HOME}/.claude/.skill-project-verified-${TOK}"
COMP="${HOME}/.claude/.skill-composition-state-${TOK}"
# Status layer: review+verify both completed, so the existing status checks pass
# and ONLY a verdict can produce a new denial.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":2,"completed":["requesting-code-review","verification-before-completion"]}' > "${COMP}"

mkinput() { jq -n --arg tp "${_TPATH}" '{"transcript_path":$tp,"tool_input":{"command":"git push origin HEAD"}}'; }
run_in() { ( cd "$1" && mkinput | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null ); }
mkart() { printf '%s' "$1" > "${ART}"; }

# ================= Verify-verdict hardening (non-routing repo, isolated) =================
NR="${TMP}/nonrouting"; mkdir -p "${NR}"
( cd "${NR}"; git init -q; git config user.email t@t; git config user.name t; echo a > f; git add -A; git commit -qm c1 )
NRHEAD="$(git -C "${NR}" rev-parse HEAD)"

# (1) failing verdict covering HEAD -> DENY (status says done, but tests failed)
mkart "$(jq -nc --arg s "${NRHEAD}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${NR}")"
assert_contains     "failing verdict at HEAD => deny"        '"deny"' "${out:-<empty>}"
assert_contains     "deny names the failing gate"           "tests"  "${out:-<empty>}"

# (2) failing verdict NOT covering HEAD (unrelated sha) -> NO deny  [FALSE-BLOCK GUARD]
mkart "$(jq -nc '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}')"
out="$(run_in "${NR}")"
assert_not_contains "stale/cross-branch fail => no deny"     '"deny"' "${out:-}"

# (3) no artifact -> NO deny on verdict grounds (status governs, unchanged)
rm -f "${ART}"
out="$(run_in "${NR}")"
assert_not_contains "absent verdict => no deny"             '"deny"' "${out:-}"

# (4) clean verdict covering HEAD -> NO deny
mkart "$(jq -nc --arg s "${NRHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${NR}")"
assert_not_contains "clean verdict => no deny"             '"deny"' "${out:-}"

# (1b) FAILING verdict at an ANCESTOR (HEAD moved past it, e.g. a fix commit) -> NO deny
# [FALSE-BLOCK GUARD, Finding A]: a failure is authoritative only for the exact commit
# it was measured at; a later HEAD may pass, so an ancestor failure must not block.
( cd "${NR}"; echo b > f2; git add -A; git commit -qm c2-fix )
mkart "$(jq -nc --arg s "${NRHEAD}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${NR}")"
assert_not_contains "ancestor failing verdict => no deny (HEAD may be fixed)" '"deny"' "${out:-}"

# ================= Routing-governance gate (routing repo) =================
RR="${TMP}/routing"; mkdir -p "${RR}"
( cd "${RR}"; git init -q; git config user.email t@t; git config user.name t
  mkdir config; echo '{}' > config/default-triggers.json; git add -A; git commit -qm c1 )
RRBASE="$(git -C "${RR}" rev-parse HEAD)"
( cd "${RR}"; git checkout -q -b feature; git branch -f main "${RRBASE}"
  mkdir hooks; echo 'echo x' > hooks/y.sh; git add -A; git commit -qm routing-change )
RRC2="$(git -C "${RR}" rev-parse HEAD)"                 # the routing commit itself
( cd "${RR}"; mkdir -p docs; echo note > docs/n.md; git add -A; git commit -qm docs-followup )
RRHEAD="$(git -C "${RR}" rev-parse HEAD)"               # docs-only commit on top of routing

# (5) routing diff + NO clean verdict -> DENY with project-verification remedy
rm -f "${ART}"
out="$(run_in "${RR}")"
assert_contains     "routing change, no verdict => deny"    '"deny"'              "${out:-<empty>}"
assert_contains     "routing deny names project-verification" "project-verification" "${out:-<empty>}"

# (6) routing diff + clean verdict AT HEAD -> NO deny
mkart "$(jq -nc --arg s "${RRHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${RR}")"
assert_not_contains "routing + clean@HEAD => no deny"       '"deny"' "${out:-}"

# (7a) clean verdict at BASE, routing files CHANGED after it -> DENY [Finding B: unverified routing delta]
mkart "$(jq -nc --arg s "${RRBASE}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${RR}")"
assert_contains     "routing changed since verdict => deny" '"deny"' "${out:-<empty>}"

# (7b) clean verdict AT the routing commit, only a docs commit after -> NO deny (advisory;
# routing unchanged since the verdict, so the benign follow-up is not re-blocked)
mkart "$(jq -nc --arg s "${RRC2}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
out="$(run_in "${RR}")"
assert_not_contains "routing verified, docs-only follow-up => no deny" '"deny"' "${out:-}"

# (8) non-routing repo + routing-named diff + no verdict -> NO deny (routing gate scoped out)
( cd "${NR}"; git checkout -q -b feature2; mkdir -p hooks; echo z > hooks/z.sh; git add -A; git commit -qm h )
rm -f "${ART}"
out="$(run_in "${NR}")"
assert_not_contains "non-routing repo => routing gate scoped out" '"deny"' "${out:-}"

# ============ Token convergence: concurrent-session singleton clobber (the live deadlock) ============
# The payload-derived guard token is session-t, but the payload-less SKILL wrote the
# verdict under a DIFFERENT token (it read a singleton later clobbered by another
# session). Binding on sha (not session token) must bridge this so the gate finds the
# clean verdict for THIS HEAD and does not false-block.
CV="${TMP}/convrepo"; mkdir -p "${CV}"
( cd "${CV}"; git init -q; git config user.email t@t; git config user.name t
  mkdir config; echo '{}' > config/default-triggers.json; git add -A; git commit -qm c1 )
CVBASE="$(git -C "${CV}" rev-parse HEAD)"
( cd "${CV}"; git checkout -q -b feature; git branch -f main "${CVBASE}"
  mkdir hooks; echo 'echo x' > hooks/y.sh; git add -A; git commit -qm routing-change )
CVHEAD="$(git -C "${CV}" rev-parse HEAD)"

# (9) routing diff, clean verdict AT HEAD but under a FOREIGN token (not session-t) -> NO deny
rm -f "${HOME}/.claude/.skill-project-verified-"*
printf '%s' "$(jq -nc --arg s "${CVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')" \
  > "${HOME}/.claude/.skill-project-verified-session-FOREIGN"
out="$(run_in "${CV}")"
assert_not_contains "foreign-token clean verdict @HEAD bridges deadlock" '"deny"' "${out:-}"

# (10) anti-gate-gaming: a foreign CLEAN@HEAD must NOT mask a foreign FAILED@HEAD.
#      Verify is in the chain (status completed), so verify-hardening must still deny,
#      naming the failing gate (deny-bias in token resolution).
rm -f "${HOME}/.claude/.skill-project-verified-"*
printf '%s' "$(jq -nc --arg s "${CVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')" \
  > "${HOME}/.claude/.skill-project-verified-session-CLEANFOREIGN"
printf '%s' "$(jq -nc --arg s "${CVHEAD}" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')" \
  > "${HOME}/.claude/.skill-project-verified-session-FAILEDFOREIGN"
out="$(run_in "${CV}")"
assert_contains "clean sibling cannot mask failed@HEAD sibling"  '"deny"' "${out:-<empty>}"
assert_contains "deny names the failing gate (deny-bias)"        "tests"  "${out:-<empty>}"

# (11) foreign token but sha is NOT HEAD (stale) -> still deny (no covering verdict) [no over-bridging]
rm -f "${HOME}/.claude/.skill-project-verified-"*
printf '%s' "$(jq -nc '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}')" \
  > "${HOME}/.claude/.skill-project-verified-session-STALEFOREIGN"
out="$(run_in "${CV}")"
assert_contains "foreign verdict not@HEAD => still deny (sha binding intact)" '"deny"' "${out:-<empty>}"

# (12) PR #121 scenario (issue #123): OWN token clean at an ANCESTOR + FOREIGN token clean at
# EXACT HEAD, routing changed after the ancestor. Pre-fix, the resolver short-circuited to the
# own ANCESTOR verdict (routing delta since it) => false DENY, shadowing the genuine exact-HEAD
# verdict on disk. Post-fix, the exact-HEAD foreign verdict OUTRANKS the own ancestor => NO deny.
rm -f "${HOME}/.claude/.skill-project-verified-"*
mkart "$(jq -nc --arg s "${CVBASE}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"   # OWN token @ ANCESTOR
printf '%s' "$(jq -nc --arg s "${CVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')" \
  > "${HOME}/.claude/.skill-project-verified-session-EXACTFOREIGN"                                          # FOREIGN @ EXACT HEAD
out="$(run_in "${CV}")"
assert_not_contains "own ancestor must not shadow foreign exact-HEAD@HEAD (PR #121, #123)" '"deny"' "${out:-}"

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
exit $?
