#!/usr/bin/env bash
# Issue #219 — the push gate must measure the tree/commit the GATED COMMAND acts
# on, not the tree the SESSION happens to be sitting in.
#
# Every cell below runs the REAL guard against REAL git repositories: the two
# deny/allow flips are the live symptoms reproduced on 2026-08-29, and each is
# paired with a control that must keep denying, so a fix that simply stops
# denying cannot pass.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-subject.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

_OLDHOME="$HOME"
TMP="$(mktemp -d /tmp/pgs-XXXXXX)"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
_TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"
TOK="session-t"
ART="${HOME}/.claude/.skill-project-verified-${TOK}"
COMP="${HOME}/.claude/.skill-composition-state-${TOK}"
# Status layer satisfied, so only a SUBJECT-dependent leg can deny.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":2,"completed":["requesting-code-review","verification-before-completion"]}' > "${COMP}"

# ---- Fixture: routing repo, a private worktree, and a concurrent session that
# ---- parks the shared checkout on ITS OWN routing branch.
RR="${TMP}/repo"; mkdir -p "${RR}"
( cd "${RR}"; git init -q -b main; git config user.email t@t; git config user.name t
  mkdir -p config; echo '{}' > config/default-triggers.json; echo base > README.md
  git add -A; git commit -qm base ) >/dev/null 2>&1
BASE="$(git -C "${RR}" rev-parse HEAD)"
git -C "${RR}" update-ref refs/remotes/origin/main "${BASE}"

# My branch, in a private worktree, touches NO routing files.
WT="${TMP}/wt"
git -C "${RR}" worktree add -q -b mine "${WT}" main >/dev/null 2>&1
( cd "${WT}"; mkdir -p tests; echo x > tests/t.sh; git add -A; git commit -qm "tests only" ) >/dev/null 2>&1
MINE="$(git -C "${WT}" rev-parse HEAD)"

# A second worktree whose branch DOES touch routing — the control subject.
WTR="${TMP}/wtr"
git -C "${RR}" worktree add -q -b mine-routing "${WTR}" main >/dev/null 2>&1
( cd "${WTR}"; echo '{"y":2}' > config/default-triggers.json; git add -A; git commit -qm "routing" ) >/dev/null 2>&1
MINER="$(git -C "${WTR}" rev-parse HEAD)"

# The concurrent session's branch, left checked out in the SHARED tree.
( cd "${RR}"; git checkout -q -b other; echo '{"x":1}' > config/default-triggers.json
  mkdir -p hooks; echo 'x' > hooks/h.sh; git add -A; git commit -qm "other routing" ) >/dev/null 2>&1

# An unrelated repository, for the security cells.
UR="${TMP}/unrelated"; mkdir -p "${UR}"
( cd "${UR}"; git init -q -b main; git config user.email t@t; git config user.name t
  echo z > z; git add -A; git commit -qm z ) >/dev/null 2>&1

mkinput() { jq -n --arg tp "${_TPATH}" --arg c "$1" --arg cw "$2" \
  '{transcript_path:$tp,cwd:$cw,tool_input:{command:$c}}'; }
# run <process-cwd> <command> [payload-cwd]
run() { ( cd "$1" && mkinput "$2" "${3:-$1}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null ); }
mkart() { printf '%s' "$1" > "${ART}"; }
clean_at() { jq -nc --arg s "$1" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}'; }

# ================= The two live #219 flips =================
# A clean verdict exists, measured against MY worktree HEAD — exactly what
# project-verification writes when run in the worktree.
mkart "$(clean_at "${MINE}")"

# (1) `git -C <worktree> push` while the shared checkout sits on another
#     session's routing branch. My branch touches ZERO routing files.
out="$(run "${RR}" "git -C ${WT} push origin mine")"
assert_not_contains "-C worktree push => no deny (subject is the worktree)" '"deny"' "${out:-}"

# (2) Same tree, no -C: the refspec names the branch being pushed.
out="$(run "${RR}" "git push origin mine")"
assert_not_contains "refspec push => no deny (subject is the named ref)" '"deny"' "${out:-}"

# (3) `cd <worktree> && git push` — the third shape a session actually types.
out="$(run "${RR}" "cd ${WT} && git push origin HEAD")"
assert_not_contains "cd-then-push => no deny (subject is the cd target)" '"deny"' "${out:-}"

# ================= Controls that MUST keep denying =================
# (4) The subject genuinely touches routing and the verdict does not cover it.
out="$(run "${RR}" "git -C ${WTR} push origin mine-routing")"
assert_contains "routing subject with no covering verdict => deny" '"deny"' "${out:-<empty>}"

# (5) Acceptance is not widened: a verdict bound to a DIFFERENT commit than the
#     subject must not satisfy the routing gate for the subject.
mkart "$(clean_at "${MINE}")"
out="$(run "${RR}" "git -C ${WTR} push origin mine-routing")"
assert_contains "verdict for another commit => still deny" '"deny"' "${out:-<empty>}"

# (6) ...and it allows once the verdict actually covers the subject.
mkart "$(clean_at "${MINER}")"
out="$(run "${RR}" "git -C ${WTR} push origin mine-routing")"
assert_not_contains "verdict covering the routing subject => allow" '"deny"' "${out:-}"

# ================= Security: an unvalidatable hint never steers the gate =====
mkart "$(clean_at "${MINE}")"
# (7) A -C path outside this repository is discarded, so the gate falls back to
#     the process cwd (which here is the concurrent routing branch) and denies.
out="$(run "${RR}" "git -C ${UR} push")"
assert_contains "-C into an unrelated repo => hint discarded, deny stands" '"deny"' "${out:-<empty>}"
# (8) A -C path that does not exist at all is likewise discarded.
out="$(run "${RR}" "git -C ${TMP}/does-not-exist push")"
assert_contains "-C into a missing dir => hint discarded, deny stands" '"deny"' "${out:-<empty>}"

# (8b) THE attack the validation actually exists for, and it is NOT cell (7):
#      a `git clone` of the SAME repo, separately checked out and clean. It is a
#      genuine git repository carrying the same branch NAMES, so a lax "is this a
#      git repo?" check would accept it and let the gate measure a tree the push
#      never touches. `--git-common-dir` differs for a clone and does NOT differ
#      for a worktree — which is the entire reason the check is written that way
#      rather than as an existence test.
CLONE="${TMP}/clone"
git clone -q "${RR}" "${CLONE}" >/dev/null 2>&1
out="$(run "${RR}" "git -C ${CLONE} push")"
assert_contains     "-C into a CLONE of the same repo => rejected, deny stands" '"deny"' "${out:-<empty>}"
assert_contains     "clone rejection is announced, not silent" "not a worktree of this repository" "${out:-<empty>}"

# ================= No-hint behaviour is unchanged =================
# (9) A bare push from the shared checkout still measures the shared checkout.
out="$(run "${RR}" "git push")"
assert_contains "bare push => subject is the process cwd (unchanged)" '"deny"' "${out:-<empty>}"

# ================= Refspec source: any revision, not just branch names ======
# Restricting the push SOURCE to branch names was a BYPASS: `git push origin
# <sha>:refs/heads/x` is an ordinary push whose source the gate then failed to
# resolve, so it fell back to the checkout HEAD. Measured pre-fix: ALLOW here,
# DENY for the equivalent named-branch push — the model could pick which tree
# the gate looked at by writing the same push a different way.
mkart "$(clean_at "${MINE}")"
out="$(run "${RR}" "git -C ${WT} push origin ${MINER}:refs/heads/x")"
assert_contains "raw-sha refspec is measured, not ignored" '"deny"' "${out:-<empty>}"
# ...and the same shape on a COVERED commit must still allow, so the cell above
# is not passing merely because sha pushes now always deny.
out="$(run "${RR}" "git -C ${WT} push origin ${MINE}:refs/heads/x")"
assert_not_contains "covered sha refspec still allows" '"deny"' "${out:-}"

# (11) A DISCARDED hint is named in the DENY itself. #198 drops advisories on a
#      deny, and that rule is deliberately overridden here: the failure #219
#      documents is a deny whose stated predicate is false of the command, so
#      which tree the decision was measured against is part of the decision.
out="$(run "${RR}" "git -C ${UR} push")"
assert_contains "discarded hint is named in the deny" "not a worktree of this repository" "${out:-<empty>}"

# (12) A refspec that is not a local branch here is likewise named, not silently
#      ignored — the gate then measures this checkout, which the user must know.
out="$(run "${RR}" "git push origin no-such-branch")"
assert_contains "unresolvable pushed ref is named" "does not resolve to any commit" "${out:-<empty>}"

# ================= A subject that is not one commit is named ================
# "No ref resolved" is ambiguous: a bare push really is HEAD, but a deletion
# carries no content and a multi-ref push carries several. Both fall through to
# HEAD, so the ambiguity is announced rather than silently measured. It is NOT
# acted on — the predicate fires if ANY push segment is partial, so suppressing
# a gate on it would let a deletion excuse a real push in the same command.
mkart "$(clean_at "${MINE}")"
out="$(run "${RR}" "git push --delete origin mine")"
assert_contains "a deletion is named as not-one-commit" "no single commit is its subject" "${out:-<empty>}"
out="$(run "${RR}" "git push --all origin")"
assert_contains "a multi-ref push is named as not-one-commit" "no single commit is its subject" "${out:-<empty>}"
# ...and the note must NOT fire on an ordinary single-ref push, or it is noise.
out="$(run "${RR}" "git -C ${WT} push origin mine")"
assert_not_contains "an ordinary push is not called partial" "no single commit is its subject" "${out:-}"

# ================= The divergence is announced (#198) =================
# (10) When the gate measured a tree other than the one it is running in, it
#      says so — silence would make a subject swap indistinguishable from the
#      old behaviour.
mkart "$(clean_at "${MINE}")"
out="$(run "${RR}" "git -C ${WT} push origin mine")"
assert_contains "subject divergence is announced" "${WT}" "${out:-<empty>}"

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
exit $?
