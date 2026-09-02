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
# carries no content and a multi-ref push carries several. #229 settles the two
# halves DIFFERENTLY, so they must no longer share one message: a deletion is
# acted on (the content legs are skipped, cells 13-17 below) while a multi-ref
# push keeps measuring HEAD and says it may under-measure. A single shared note
# for both is what made the deletion false-block invisible.
mkart "$(clean_at "${MINE}")"
out="$(run "${RR}" "git push --delete origin mine")"
assert_contains "a deletion is named as shipping no content" "ships no content" "${out:-<empty>}"
out="$(run "${RR}" "git push --all origin")"
assert_contains "a multi-ref push is named as not-one-commit" "no single commit is its subject" "${out:-<empty>}"
# ...and the note must NOT fire on an ordinary single-ref push, or it is noise.
out="$(run "${RR}" "git -C ${WT} push origin mine")"
assert_not_contains "an ordinary push is not called partial" "no single commit is its subject" "${out:-}"
assert_not_contains "an ordinary push is not called a deletion" "ships no content" "${out:-}"


# ================= Deletion-only pushes skip the content legs (#229) ========
# A command whose EVERY push segment deletes a ref ships no content, so the
# content-dependent legs have no subject: measuring them at this checkout's HEAD
# answers a question about a commit the command does not send. Each flip below
# is paired with a control that MUST keep denying, so a fix that merely stopped
# denying cannot pass.
mkart "$(clean_at "${MINE}")"   # covers MY worktree, NOT the shared routing HEAD

# (13) Control first: from the shared checkout (parked on a routing branch with
#      no covering verdict) an ordinary push of that branch DENIES.
out="$(run "${RR}" "git push origin other")"
assert_contains     "control: ordinary push of the routing branch denies" '"deny"' "${out:-<empty>}"
#      ...and the same ref as a DELETION ships nothing, so it must not.
out="$(run "${RR}" "git push --delete origin other")"
assert_not_contains "deletion-only push => routing governance does not fire" '"deny"' "${out:-}"
assert_contains     "deletion-only push says it ships no content" "ships no content" "${out:-<empty>}"

# (14) THE controls the ALL-form exists for: a deletion must never excuse a real
#      push in the same command. Both of these still deny.
out="$(run "${RR}" "git push --delete origin mine; git push origin other")"
assert_contains "deletion followed by a real push => still deny" '"deny"' "${out:-<empty>}"
# Note the real push must name a branch that ACTUALLY carries routing changes:
# with `main` here the cell passed for the wrong reason — `main` equals the
# mainline base, so its diff is empty and nothing would have denied even without
# the deletion. A control that cannot deny proves nothing about the skip.
out="$(run "${RR}" "git push origin other && git push --delete origin mine")"
assert_contains "real push followed by a deletion => still deny" '"deny"' "${out:-<empty>}"
out="$(run "${RR}" "git push origin :mine other")"
assert_contains "deletion mixed with a live refspec => still deny" '"deny"' "${out:-<empty>}"

# (14b) THE regression this predicate's segment whitelist exists for, and it is
#       not a syntax trick: a git ALIAS reports its own word from
#       `_gc_segment_git_sub`, never `push`, so the second segment is invisible
#       to every precise predicate here — while still pushing real content.
#       Measured before the fix: this ALLOWED, with the guard announcing "ships
#       no content", on a branch whose routing change had no covering verdict.
#       Everywhere else in this lib the string-detection ceiling degrades to
#       "measure HEAD" (safe); certifying deletion-only made it degrade to
#       "skip the gate", which is why this one had to be closed rather than
#       documented. An alias in ~/.gitconfig works the same way — nothing about
#       this needs the inline `-c` form.
out="$(run "${RR}" "git push --delete origin mine && git -c alias.p=push p origin other")"
assert_contains "alias-hidden push in a deletion command => still deny" '"deny"' "${out:-<empty>}"
assert_not_contains "...and the gate does not claim it ships no content" "ships no content" "${out:-}"
# Same shape with an opaque segment rather than an alias — the subcommand is not
# the discriminator, "can we account for this segment at all" is.
out="$(run "${RR}" "git push --delete origin mine && ./deploy.sh")"
assert_contains "opaque segment in a deletion command => still deny" '"deny"' "${out:-<empty>}"
# (14c) A command substitution runs wherever it appears — including inside the
#       arguments of the recognised deletion itself, which is why the guard for
#       it is whole-command rather than scoped to the segment whitelist.
out="$(run "${RR}" "git push --delete origin mine && cd \$(git push origin other)")"
assert_contains "substitution in a deletion command => still deny" '"deny"' "${out:-<empty>}"
# (14d) And an UNTRUSTWORTHY PARSE cannot certify. `\\'` is a literal quote to
#       real bash but toggles quote mode in this scanner, merging a genuine `;`
#       and a real push into one segment whose first word is `cd`. It contains
#       no substitution syntax at all, so it evades the guard above; the
#       scanner's own `_GC_UNBALANCED` is what catches it.
out="$(run "${RR}" "git push --delete origin mine; cd \\'; git push origin other")"
assert_contains "unbalanced parse in a deletion command => still deny" '"deny"' "${out:-<empty>}"
assert_not_contains "...and it does not claim to ship no content" "ships no content" "${out:-}"
# ...and the bounded cost is visible: a compound whose extra segment is inert
# still certifies, so the whitelist has not simply disabled the fix.
out="$(run "${RR}" "cd ${WT} && git push --delete origin mine")"
assert_not_contains "cd + deletion still skips the content legs" '"deny"' "${out:-}"

# (15) Multi-ref is deliberately NOT narrowed (#229 records the decision):
#      it keeps measuring HEAD, and now says that it may under-measure.
out="$(run "${RR}" "git push --all origin")"
assert_contains "--all still measured at HEAD => deny stands" '"deny"' "${out:-<empty>}"
assert_contains "--all is announced as possibly under-measuring" "UNDER-measure" "${out:-<empty>}"
# ...and it must NOT claim the deletion skip, or the two shapes are conflated
# again — which is the conflation this issue exists to undo.
assert_not_contains "--all does not claim the deletion skip" "ships no content" "${out:-}"

# (16) verify-hardening is a content leg too: a FAILING verdict at the checkout
#      HEAD is authoritative for that commit, which a deletion does not push.
_HEADSHA="$(git -C "${RR}" rev-parse HEAD)"
jq -nc --arg s "${_HEADSHA}" \
  '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${ART}"
out="$(run "${RR}" "git push origin other")"
assert_contains     "control: failing verdict at HEAD denies an ordinary push" "failing gate" "${out:-<empty>}"
out="$(run "${RR}" "git push --delete origin other")"
assert_not_contains "failing verdict at HEAD does not deny a deletion" '"deny"' "${out:-}"
mkart "$(clean_at "${MINE}")"

# (17) The deliberate BOUNDARY: the composition-chain gates are not content
#      legs. Deleting a remote ref is still an outbound action, so REVIEW/VERIFY
#      still apply to it — narrowing the subject must not become "a deletion is
#      ungated".
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' > "${COMP}"
out="$(run "${RR}" "git push --delete origin other")"
assert_contains "a deletion still faces the REVIEW/VERIFY gates" '"deny"' "${out:-<empty>}"
#      Assert WHICH gate denied, not merely that something did. Asserting only
#      `"deny"` passed even when the deletion skip was wrongly widened to the
#      REVIEW gate, because VERIFY then denied instead and the cell could not
#      tell the difference — mutation-measured.
assert_contains "...and it is the REVIEW gate that denies" "requesting-code-review has not run" "${out:-<empty>}"
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":2,"completed":["requesting-code-review","verification-before-completion"]}' > "${COMP}"
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
