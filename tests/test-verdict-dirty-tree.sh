#!/usr/bin/env bash
# tests/test-verdict-dirty-tree.sh — #274
#
# A verdict names a COMMIT and measures the WORKING TREE. Those are the same
# thing only when the tree is clean, and `worktree_dirty` is deliberately
# advisory: verifying uncommitted work and committing afterwards is supported,
# so denying would break a real workflow. What was missing is the #198 half —
# the gate accepted such a verdict as covering HEAD and never said the measured
# tree differed from the named one. Two occurrences recorded 2026-09-19.
#
# Every advisory cell is PAIRED with a clean-tree control that must stay silent,
# because "the advisory fired" and "the guard prints more than it used to" are
# indistinguishable without one.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-verdict-dirty-tree.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
VLIB="${PROJECT_ROOT}/hooks/lib/verdict.sh"
FIX="${SCRIPT_DIR}/fixtures/verdict-dirty-tree"
NEEDLE="VERDICT SCOPE"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq unavailable — this file asserts JSON record shape and cannot degrade"; exit 1
fi

_OLDHOME="$HOME"
TMP="$(mktemp -d /tmp/vdt-XXXXXX)"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
_TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"
TOK="session-t"
ART="${HOME}/.claude/.skill-project-verified-${TOK}"
COMP="${HOME}/.claude/.skill-composition-state-${TOK}"
# Two composition states, because the two acceptance points are reached under
# DIFFERENT preconditions and a single state exercises only one of them.
#   full    — both milestones in `.completed`; the chain gate is satisfied by
#             status, so routing-governance is the leg that consults the verdict.
#   review  — only the review milestone; VERIFY is missing from status, so the
#             chain leg is the one that accepts a clean covering verdict.
# The first cut used `full` throughout: the VERIFY-leg branch is guarded on
# `_g_verify = false`, so it never executed and four cells passed against a
# wiring that did not exist.
INVOC="${HOME}/.claude/.skill-invocation-evidence-${TOK}"
set_comp() {
    case "$1" in
        full)
            rm -f "${INVOC}"
            printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":2,"completed":["requesting-code-review","verification-before-completion"]}' > "${COMP}" ;;
        no-chain-verdict-verify)
            # NO composition chain: the chain block's VERIFY gate does not read
            # the verdict at all, it denies outright on a missing milestone, so
            # with a chain present the global leg is never reached. REVIEW comes
            # from invocation evidence; VERIFY is left for the verdict to supply.
            rm -f "${COMP}"
            printf '%s' '["requesting-code-review"]' > "${INVOC}" ;;
    esac
}
set_comp full

mkinput() { jq -n --arg tp "${_TPATH}" '{"transcript_path":$tp,"tool_input":{"command":"git push origin HEAD"}}'; }
run_in()  { ( cd "$1" && mkinput | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null ); }
# seed <fixture-basename> <sha>
seed()    { sed "s/@SHA@/$2/" "${FIX}/$1.json" > "${ART}"; }

# ---- fixture repos ---------------------------------------------------------
# Non-routing: the chain VERIFY leg is the acceptance point.
NR="${TMP}/nonrouting"; mkdir -p "${NR}"
( cd "${NR}"; git init -q; git config user.email t@t; git config user.name t
  echo a > f; git add -A; git commit -qm c1 )
NRHEAD="$(git -C "${NR}" rev-parse HEAD)"

# Routing: routing-governance is the SECOND acceptance point, and it is a
# separate code path — a fix wired into only one of them passes half the suite.
RR="${TMP}/routing"; mkdir -p "${RR}"
( cd "${RR}"; git init -q; git config user.email t@t; git config user.name t
  mkdir config; echo '{}' > config/default-triggers.json; git add -A; git commit -qm c1 )
RRBASE="$(git -C "${RR}" rev-parse HEAD)"
( cd "${RR}"; git checkout -q -b feature; git branch -f main "${RRBASE}"
  mkdir hooks; echo 'echo x' > hooks/y.sh; git add -A; git commit -qm routing-change )
RRHEAD="$(git -C "${RR}" rev-parse HEAD)"

# ---- (1) the WRITER records the path list, not just the boolean -------------
# Driven through the real script in a real repo: a hand-written record would
# only prove the readers below agree with this file's idea of the format.
WR="${TMP}/writer"; mkdir -p "${WR}"
( cd "${WR}"; git init -q; git config user.email t@t; git config user.name t
  printf 'substrate: local\ncommands:\n  - name: noop\n    run: "true"\nfail_fast: false\n' > .verify.yml
  echo one > a.txt; echo two > b.txt; git add -A; git commit -qm c1 )
_VR_OUT="${HOME}/.claude/.skill-project-verified-session-writer"
# clean tree first: the control for the dirty run below
( cd "${WR}" && SKILL_SESSION_TOKEN=session-writer bash "${PROJECT_ROOT}/scripts/verify-and-record.sh" >/dev/null 2>&1 )
assert_equals "clean tree => worktree_dirty false"  "false" "$(jq -r '.worktree_dirty' "${_VR_OUT}" 2>/dev/null)"
assert_equals "clean tree => empty dirty_paths"     "0"     "$(jq -r '(.dirty_paths // []) | length' "${_VR_OUT}" 2>/dev/null)"

( cd "${WR}"; echo changed > a.txt; echo changed > b.txt )
( cd "${WR}" && SKILL_SESSION_TOKEN=session-writer bash "${PROJECT_ROOT}/scripts/verify-and-record.sh" >/dev/null 2>&1 )
assert_equals "dirty tree => worktree_dirty true"   "true"  "$(jq -r '.worktree_dirty' "${_VR_OUT}" 2>/dev/null)"
assert_equals "dirty tree => both paths recorded"   "2"     "$(jq -r '(.dirty_paths // []) | length' "${_VR_OUT}" 2>/dev/null)"
assert_contains "dirty_paths names the edited file" "a.txt" "$(jq -r '(.dirty_paths // []) | join(" ")' "${_VR_OUT}" 2>/dev/null)"
assert_equals "dirty_path_count agrees with the list" "2"   "$(jq -r '.dirty_path_count // -1' "${_VR_OUT}" 2>/dev/null)"
# The boolean is format-frozen for existing readers; the list is additive.
assert_equals "worktree_dirty is still a boolean"   "boolean" "$(jq -r '.worktree_dirty | type' "${_VR_OUT}" 2>/dev/null)"

# ---- (1b) the writer records REAL path names, not git's quoted rendering ---
# Plain --porcelain applies C-style quoting to anything non-ASCII: measured,
# a backslash, a quote and a UTF-8 name came back as "back\\slash.txt",
# "quote\"name.txt" and "unicode-\303\274.txt". The advisory exists so a
# reader can judge whether the uncommitted paths matter to what they are
# pushing, and an octal-escaped name cannot be matched against the one they
# know. A rename must also be ONE entry, not a "old -> new" pair counted as a
# single path.
QR="${TMP}/quoted"; mkdir -p "${QR}"
( cd "${QR}"; git init -q; git config user.email t@t; git config user.name t
  printf 'substrate: local\ncommands:\n  - name: noop\n    run: "true"\nfail_fast: false\n' > .verify.yml
  printf 'a\n' > 'plain.txt'
  printf 'b\n' > 'with space.txt'
  printf 'c\n' > 'quote"name.txt'
  printf 'd\n' > 'back\slash.txt'
  printf 'e\n' > 'unicode-ü.txt'
  printf 'f\n' > 'to-rename.txt'
  git add -A >/dev/null 2>&1; git commit -qm c1
  printf 'A\n' > 'plain.txt'; printf 'B\n' > 'with space.txt'
  printf 'C\n' > 'quote"name.txt'; printf 'D\n' > 'back\slash.txt'
  printf 'E\n' > 'unicode-ü.txt'
  git mv 'to-rename.txt' 'renamed.txt' >/dev/null 2>&1 )
_QOUT="${HOME}/.claude/.skill-project-verified-session-quoted"
( cd "${QR}" && SKILL_SESSION_TOKEN=session-quoted bash "${PROJECT_ROOT}/scripts/verify-and-record.sh" >/dev/null 2>&1 )
_QP="$(jq -r '(.dirty_paths // []) | join("|")' "${_QOUT}" 2>/dev/null)"
assert_equals   "a verdict is still written for an awkward tree" "true" \
    "$([ -f "${_QOUT}" ] && jq -e . "${_QOUT}" >/dev/null 2>&1 && echo true || echo false)"
assert_contains "a UTF-8 path is recorded as itself"    "unicode-ü.txt"    "${_QP:-<empty>}"
assert_contains "a quote in a path is recorded as itself" 'quote"name.txt' "${_QP:-<empty>}"
assert_contains "a backslash in a path is recorded as itself" 'back\slash.txt' "${_QP:-<empty>}"
assert_contains "a space in a path is recorded as itself" "with space.txt"  "${_QP:-<empty>}"
# The rename is the new path, once — not "old -> new" counted as one path.
assert_contains "a rename records the new path"          "renamed.txt"      "${_QP:-<empty>}"
assert_not_contains "a rename is not recorded as a pair" "->"               "${_QP:-}"

# ---- (2) the READERS -------------------------------------------------------
( set +u
  . "${VLIB}"
  export HOME
  _r_dirty=n; _r_clean=n
  seed dirty-with-paths "${NRHEAD}"
  verdict_measured_dirty "${TOK}" && _r_dirty=y
  _note="$(verdict_dirty_note "${TOK}")"
  seed clean-tree "${NRHEAD}"
  verdict_measured_dirty "${TOK}" && _r_clean=y
  _cnote="$(verdict_dirty_note "${TOK}")"
  seed dirty-legacy-no-paths "${NRHEAD}"
  _lnote="$(verdict_dirty_note "${TOK}")"
  seed dirty-truncated "${NRHEAD}"
  _tnote="$(verdict_dirty_note "${TOK}")"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' "${_r_dirty}" "${_r_clean}" "${_note}" "${_cnote}" "${_lnote}" "${_tnote}"
) > "${TMP}/readers.txt"
assert_equals   "reader: dirty record reads dirty"      "y" "$(sed -n 1p "${TMP}/readers.txt")"
assert_equals   "reader: clean record reads clean"      "n" "$(sed -n 2p "${TMP}/readers.txt")"
assert_contains "reader: note names a path"  "openspec-guard.sh" "$(sed -n 3p "${TMP}/readers.txt")"
assert_equals   "reader: clean record yields no note"   ""  "$(sed -n 4p "${TMP}/readers.txt")"
# A pre-#274 record is dirty with no list. An empty note is what the guard
# branches on to say "cannot say which paths" — fabricating one would be worse.
assert_equals   "reader: legacy record yields no note"  ""  "$(sed -n 5p "${TMP}/readers.txt")"
# Truncation: ONE remainder, counted against the true total (37 - 5 = 32), and
# the cap stated as a fact about the RECORD. The first cut counted "+k more"
# over the stored list and "(list truncated)" over the cap — two populations in
# one sentence, neither of them the number the reader wants.
_TNOTE="$(sed -n 6p "${TMP}/readers.txt")"
assert_contains "reader: truncated note states the true total"   "37 path(s)"              "${_TNOTE:-<empty>}"
assert_contains "reader: remainder counts from the true total"   "+32 more"                "${_TNOTE:-<empty>}"
assert_contains "reader: the cap is stated about the record"     "only the first 20 were recorded" "${_TNOTE:-<empty>}"
assert_not_contains "reader: the two populations are not mixed"  "list truncated"          "${_TNOTE:-}"

# ---- (3) chain VERIFY acceptance: advisory + silent control ----------------
# VERIFY absent from status, so the clean covering verdict is what satisfies it.
set_comp no-chain-verdict-verify
seed clean-tree "${NRHEAD}"
out_clean="$(run_in "${NR}")"
assert_not_contains "CONTROL: clean-tree verdict adds no scope advisory" "${NEEDLE}" "${out_clean:-}"
assert_not_contains "CONTROL: clean-tree verdict still allows"           '"deny"'    "${out_clean:-}"

seed dirty-with-paths "${NRHEAD}"
out_dirty="$(run_in "${NR}")"
assert_contains     "global VERIFY leg: dirty verdict is announced"   "${NEEDLE}"           "${out_dirty:-<empty>}"
assert_contains     "global VERIFY leg: advisory names the path"      "openspec-guard.sh"   "${out_dirty:-<empty>}"
# The decision must not move. An advisory that changes allow/deny is a new gate.
assert_not_contains "global VERIFY leg: dirty verdict still allows"   '"deny"'              "${out_dirty:-}"

seed dirty-legacy-no-paths "${NRHEAD}"
out_legacy="$(run_in "${NR}")"
assert_contains     "global VERIFY leg: legacy dirty verdict is announced" "${NEEDLE}"       "${out_legacy:-<empty>}"
assert_contains     "global VERIFY leg: legacy advisory admits it cannot name paths" "does not say which paths" "${out_legacy:-<empty>}"

# ---- (4) routing-governance acceptance: the second, separate path ----------
set_comp full
seed clean-tree "${RRHEAD}"
outr_clean="$(run_in "${RR}")"
assert_not_contains "CONTROL: routing clean-tree verdict adds no advisory" "${NEEDLE}" "${outr_clean:-}"
assert_not_contains "CONTROL: routing clean-tree verdict still allows"     '"deny"'    "${outr_clean:-}"

seed dirty-with-paths "${RRHEAD}"
outr_dirty="$(run_in "${RR}")"
assert_contains     "routing leg: dirty verdict is announced"  "${NEEDLE}" "${outr_dirty:-<empty>}"
assert_not_contains "routing leg: dirty verdict still allows"  '"deny"'    "${outr_dirty:-}"

# ---- (5) the advisory is emitted ONCE, when BOTH legs accept ---------------
# The dedup flag only does anything when both acceptance points fire in one run,
# and that needs a routing repo WITH no chain: the global leg then takes VERIFY
# from the verdict and routing-governance accepts the same verdict afterwards.
# Measured: with `set_comp full` the global leg is satisfied by `.completed` and
# never calls the writer, so the earlier version of this cell passed with the
# dedup deleted — it pinned nothing.
set_comp no-chain-verdict-verify
seed dirty-with-paths "${RRHEAD}"
out_both="$(run_in "${RR}")"
assert_contains "both legs accept => advisory present" "${NEEDLE}" "${out_both:-<empty>}"
assert_not_contains "both legs accept => still allows" '"deny"'    "${out_both:-}"
_n="$(printf '%s' "${out_both}" | grep -o "${NEEDLE}" | wc -l | tr -d ' ')"
assert_equals "advisory appears exactly once when both legs accept" "1" "${_n}"

# ---- (6) a DENY still drops the advisory (#198 boundary) --------------------
# Where a deny fires the guard emits one object and the user is already stopped.
set_comp full
rm -f "${ART}"
out_deny="$(run_in "${RR}")"
assert_contains     "routing change with no verdict still denies" '"deny"'   "${out_deny:-<empty>}"
assert_not_contains "a deny carries no scope advisory"            "${NEEDLE}" "${out_deny:-}"

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary
