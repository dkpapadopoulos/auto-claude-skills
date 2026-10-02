#!/usr/bin/env bash
# test-verify-measured-verdict.sh — VERIFY measured-verdict leg (#301).
#
# The push gate's VERIFY leg credits INVOCATION: Skill(verification-before-
# completion) returns its instruction body and the milestone is recorded, so
# invoking the skill and executing nothing satisfies the gate. This leg asks,
# advisory-only, whether a verdict MEASURED by scripts/verify-and-record.sh
# covers the pushed commit, and records what it would have blocked.
#
# Pinned here: the reader predicates in hooks/lib/verdict.sh, the recorder
# hooks/lib/verify-shadow.sh, the leg in hooks/openspec-guard.sh, and the
# corpus reader scripts/verify-shadow-adjudicate.sh — which ships in the same
# change as the writer because #239's corpus reached its floor unseen.
#
# Measured verdicts are produced by the REAL verify-and-record.sh, never
# hand-written: a hand-written "measured" fixture only proves the predicate
# agrees with this file's idea of the producer. Reader corpora are produced by
# the REAL recorder for the same reason; only `ts` is patched afterwards.
#
# Bash 3.2 compatible. Assertion loops are heredoc-fed, never piped.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERDICT_LIB="${PROJECT_ROOT}/hooks/lib/verdict.sh"
SHADOW_LIB="${PROJECT_ROOT}/hooks/lib/verify-shadow.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
PRODUCER="${PROJECT_ROOT}/scripts/verify-and-record.sh"
READER="${PROJECT_ROOT}/scripts/verify-shadow-adjudicate.sh"
DESIGN="${PROJECT_ROOT}/openspec/changes/verify-measured-verdict/design.md"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-verify-measured-verdict.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required for this test" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# 0. Artifacts exist. Bail loudly rather than vacuously passing.
# ---------------------------------------------------------------------------
_missing=""
for _f in "${VERDICT_LIB}" "${SHADOW_LIB}" "${GUARD}" "${PRODUCER}" "${READER}"; do
    if [ -f "${_f}" ]; then _record_pass "exists: ${_f#"${PROJECT_ROOT}"/}"
    else _record_fail "exists: ${_f#"${PROJECT_ROOT}"/}" "no file"; _missing="yes"; fi
done
if [ -n "${_missing}" ]; then
    _record_fail "every artifact present so the rest of the suite can run" "aborting remaining assertions"
    print_summary
    exit 1
fi

# shellcheck disable=SC1090
. "${VERDICT_LIB}"
# shellcheck disable=SC1090
. "${SHADOW_LIB}"

for _fn in verdict_discovery_source verdict_is_measured verdict_measured_class verify_shadow_record; do
    if command -v "${_fn}" >/dev/null 2>&1; then _record_pass "defines ${_fn}"
    else _record_fail "defines ${_fn}" "function undefined after sourcing"; fi
done

# ---------------------------------------------------------------------------
# Fixtures: isolated HOME, two repos with DISTINCT origins, one worktree.
#   RA — declares .verify.yml (the verify-yml producer path)
#   RB — declares nothing    (the explicit producer path)
# Neither is a routing repo (no config/default-triggers.json): routing-
# governance would deny a verdict-less push and no cell below could observe
# this leg's "absent" class.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d /tmp/vmv-XXXXXX)"
TMP="$(cd "${TMP}" && pwd -P)"
_OLDHOME="${HOME}"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
trap 'export HOME="${_OLDHOME}"; rm -rf "${TMP}"' EXIT

_mkrepo() { # <dir> <origin-url> <with-verify-yml:yes|no>
    mkdir -p "$1"
    (
      cd "$1" || exit 1
      git -c init.defaultBranch=main init -q
      git config user.email t@t; git config user.name t
      git remote add origin "$2"
      [ "$3" = "yes" ] && printf 'substrate: local\ncommands:\n  - name: tests\n    run: true\n' > .verify.yml
      echo readme > README.md
      printf '#!/bin/bash\necho hi\n' > run.sh
      git add -A; git commit -qm base
      git checkout -qb feat
      echo "# c1" >> run.sh; git commit -qam c1
    ) >/dev/null 2>&1
}
RA="${TMP}/ra"; RB="${TMP}/rb"
_mkrepo "${RA}" "https://example.invalid/org/a.git" yes
_mkrepo "${RB}" "https://example.invalid/org/b.git" no
RA_WT="${TMP}/ra-wt"
git -C "${RA}" worktree add -q -b other "${RA_WT}" main >/dev/null 2>&1

_TOK="session-t"
_ART="${HOME}/.claude/.skill-project-verified-${_TOK}"
_TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"   # basename "t" -> token "session-t"
_VLOG="${TMP}/verify-shadow.jsonl"

_bool() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
_head() { git -C "$1" rev-parse HEAD; }

# The REAL producer. Never hand-write a "measured" verdict.
_produce() { # <repo> [explicit args...]
    local _r="$1"; shift
    ( cd "${_r}" && SKILL_SESSION_TOKEN="${_TOK}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        /bin/bash "${PRODUCER}" "$@" < /dev/null ) >/dev/null 2>&1
}
# A hand-AUTHORED verdict, in the shape project-verification's last-resort
# Step 3 instructs the model to write.
_handwrite() { # <repo> <discovery_source|-omit->
    if [ "$2" = "-omit-" ]; then
        jq -nc --arg s "$(_head "$1")" \
            '{substrate:"local",passed:["tests"],failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${_ART}"
    else
        jq -nc --arg s "$(_head "$1")" --arg d "$2" \
            '{substrate:"local",discovery_source:$d,passed:["tests"],failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${_ART}"
    fi
}

# ---------------------------------------------------------------------------
# 1. Predicate units
# ---------------------------------------------------------------------------
rm -f "${_ART}"
assert_equals "absent artifact => not measured" "1" "$(_bool verdict_is_measured "${_TOK}")"
assert_equals "absent artifact => class unexplained/absent" \
    "unexplained absent" "$(verdict_measured_class "${_TOK}" "${RA}")"

_produce "${RA}"
assert_equals "REAL producer, declared gate => discovery_source verify-yml" \
    "verify-yml" "$(verdict_discovery_source "${_TOK}")"
assert_equals "REAL producer, declared gate => measured" "0" "$(_bool verdict_is_measured "${_TOK}")"
assert_equals "REAL producer, declared gate => class measured" \
    "measured ok" "$(verdict_measured_class "${_TOK}" "${RA}")"

rm -f "${_ART}"
_produce "${RB}" --name tests --run true
assert_equals "REAL producer, explicit gate => discovery_source explicit" \
    "explicit" "$(verdict_discovery_source "${_TOK}")"
assert_equals "REAL producer, explicit gate => class measured" \
    "measured ok" "$(verdict_measured_class "${_TOK}" "${RB}")"

rm -f "${_ART}"
_produce "${RB}" --name tests --run false
assert_equals "REAL producer, FAILING gate => not-clean, never measured-ok" \
    "unexplained not-clean" "$(verdict_measured_class "${_TOK}" "${RB}")"

while IFS= read -r _src; do
    [ -n "${_src}" ] || continue
    _handwrite "${RA}" "${_src}"
    assert_equals "hand-authored rung '${_src}' => not measured" "1" "$(_bool verdict_is_measured "${_TOK}")"
    assert_equals "hand-authored rung '${_src}' => explained_ladder" \
        "explained_ladder hand-authored" "$(verdict_measured_class "${_TOK}" "${RA}")"
done <<EOF
claude-md-commands
contributing-md
heuristic:package.json
EOF

_handwrite "${RA}" "something-else"
assert_equals "unrecognised source => unexplained, not explained_ladder" \
    "unexplained unrecognised-source" "$(verdict_measured_class "${_TOK}" "${RA}")"

# A near-miss of an accepted value must not be accepted: the predicate is an
# exact match, not a prefix or substring test.
while IFS= read -r _src; do
    [ -n "${_src}" ] || continue
    _handwrite "${RA}" "${_src}"
    assert_equals "near-miss '${_src}' => not measured" "1" "$(_bool verdict_is_measured "${_TOK}")"
done <<EOF
verify-yml-ish
not-explicit
explicit2
EXPLICIT
EOF

_handwrite "${RA}" "-omit-"
assert_equals "omitted discovery_source => cannot_check, never unexplained" \
    "cannot_check no-discovery-source" "$(verdict_measured_class "${_TOK}" "${RA}")"

# ORDER: "could we read it" is decided before "does it cover the commit". An
# artifact that omits the field AND is bound elsewhere is still cannot_check —
# with the two checks swapped it would read unexplained/unbound and move the
# pre-registered count on a record nobody could classify.
jq -c '.sha = "0000000000000000000000000000000000000000"' "${_ART}" > "${_ART}.t" && mv "${_ART}.t" "${_ART}"
assert_equals "omitted discovery_source AND unbound => still cannot_check" \
    "cannot_check no-discovery-source" "$(verdict_measured_class "${_TOK}" "${RA}")"
_handwrite "${RA}" "-omit-"

jq -c '.discovery_source = 7' "${_ART}" > "${_ART}.t" && mv "${_ART}.t" "${_ART}"
assert_equals "non-string discovery_source => cannot_check" \
    "cannot_check no-discovery-source" "$(verdict_measured_class "${_TOK}" "${RA}")"

printf 'not json at all\n' > "${_ART}"
assert_equals "unparseable artifact => cannot_check" \
    "cannot_check unparseable" "$(verdict_measured_class "${_TOK}" "${RA}")"
: > "${_ART}"
assert_equals "EMPTY artifact => cannot_check (zero documents is not a verdict)" \
    "cannot_check unparseable" "$(verdict_measured_class "${_TOK}" "${RA}")"
printf '[]\n' > "${_ART}"
assert_equals "non-object artifact => cannot_check" \
    "cannot_check unparseable" "$(verdict_measured_class "${_TOK}" "${RA}")"

# A measured verdict for ANOTHER commit does not cover this one.
_produce "${RA}"
_MAIN_SHA="$(git -C "${RA}" rev-parse main)"
jq -c --arg s "0000000000000000000000000000000000000000" '.sha = $s' "${_ART}" > "${_ART}.t" && mv "${_ART}.t" "${_ART}"
assert_equals "measured but bound to an unrelated sha => unexplained/unbound" \
    "unexplained unbound" "$(verdict_measured_class "${_TOK}" "${RA}")"

# ---------------------------------------------------------------------------
# 2. Guard e2e — the four spec scenarios, against the REAL guard.
# ---------------------------------------------------------------------------
_mkinput() {
    jq -n --arg tp "${_TPATH}" --arg cmd "$1" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}
_seed_status() { # <completed-json-array>
    jq -nc --argjson c "$1" \
        '{chain:["requesting-code-review","verification-before-completion"], completed:$c}' \
        > "${HOME}/.claude/.skill-composition-state-${_TOK}"
}
_BOTH='["requesting-code-review","verification-before-completion"]'
_guard() { # <plugin_root> <cwd> <command>
    ( cd "$2" && _mkinput "$3" \
        | VERIFY_SHADOW_LOG="${_VLOG}" REVIEW_SHADOW_LOG="${TMP}/rs.jsonl" \
          IMPLEMENT_SHADOW_LOG="${TMP}/is.jsonl" CLAUDE_PLUGIN_ROOT="$1" \
          bash "$1/hooks/openspec-guard.sh" 2>/dev/null )
}
_nrec() { if [ -f "${_VLOG}" ]; then grep -c . "${_VLOG}" | tr -d '[:space:]'; else echo 0; fi; }
_lastf() { if [ -f "${_VLOG}" ]; then tail -1 "${_VLOG}" | jq -r "$1" 2>/dev/null; else echo "<no-log>"; fi; }

# --- Scenario 1: invoke the skill, execute nothing -------------------------
rm -f "${_ART}" "${_VLOG}"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_equals       "S1 milestone credited, no verdict => one shadow record" "1" "$(_nrec)"
assert_equals       "S1 classification"   "unexplained" "$(_lastf .classification)"
assert_equals       "S1 reason"           "absent"      "$(_lastf .reason)"
assert_equals       "S1 would_block"      "true"        "$(_lastf .would_block)"
assert_contains     "S1 advisory names the leg"           "VERIFY VERDICT" "${out:-<empty>}"
assert_contains     "S1 advisory is the ABSENT text"      "no verification verdict covers" "${out:-<empty>}"
assert_not_contains "S1 advisory never denies"            '"deny"'         "${out:-}"
assert_not_contains "S1 emits no permissionDecision"      'permissionDecision' "${out:-}"

# --- Scenario 2: hand-authored ladder verdict ------------------------------
rm -f "${_VLOG}"; _handwrite "${RA}" "claude-md-commands"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_equals       "S2 hand-authored => one shadow record" "1" "$(_nrec)"
assert_equals       "S2 classification explained_ladder" "explained_ladder" "$(_lastf .classification)"
assert_equals       "S2 would_block" "true" "$(_lastf .would_block)"
assert_equals       "S2 records the rung" "claude-md-commands" "$(_lastf .discovery_source)"
assert_contains     "S2 advisory says hand-authored" "hand-authored" "${out:-<empty>}"
assert_not_contains "S2 push proceeds (no deny)" '"deny"' "${out:-}"

# --- Scenario 3: measured verdict is silent --------------------------------
rm -f "${_VLOG}" "${_ART}"; _produce "${RA}"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_equals       "S3 measured (verify-yml) => NO shadow record" "0" "$(_nrec)"
assert_not_contains "S3 measured (verify-yml) => no advisory" "VERIFY VERDICT" "${out:-}"
rm -f "${_VLOG}" "${_ART}"; _produce "${RB}" --name tests --run true; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RB}" "git push origin HEAD")"
assert_equals       "S3 measured (explicit) => NO shadow record" "0" "$(_nrec)"
assert_not_contains "S3 measured (explicit) => no advisory" "VERIFY VERDICT" "${out:-}"

# --- Scenario 4: unreadable verdict is cannot_check ------------------------
rm -f "${_VLOG}"; printf 'not json\n' > "${_ART}"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_equals       "S4 unparseable => one shadow record" "1" "$(_nrec)"
assert_equals       "S4 unparseable => cannot_check" "cannot_check" "$(_lastf .classification)"
assert_equals       "S4 cannot_check is not a would-block" "false" "$(_lastf .would_block)"
assert_contains     "S4 says it could not check" "could not check" "${out:-<empty>}"
assert_not_contains "S4 makes no 'nothing ran' claim" "no verification verdict covers" "${out:-}"
assert_not_contains "S4 never denies" '"deny"' "${out:-}"
rm -f "${_VLOG}"; _handwrite "${RA}" "-omit-"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_equals       "S4 omitted discovery_source => cannot_check" "cannot_check" "$(_lastf .classification)"

# --- Record shape: every field the reader keys on is present ---------------
rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "record: schema_version"    "2" "$(_lastf .schema_version)"
assert_equals "record: predicate_version" "2" "$(_lastf .predicate_version)"
assert_equals "record: gate_declaration is recorded (declared, local)" "local" "$(_lastf .gate_declaration)"
assert_equals "record: repo is the toplevel" "${RA}" "$(_lastf .repo)"
assert_equals "record: repo_id is the ORIGIN (normalised), not the path" "example.invalid/org/a" "$(_lastf .repo_id)"
assert_equals "record: branch"   "feat" "$(_lastf .branch)"
assert_equals "record: head_sha" "$(_head "${RA}")" "$(_lastf .head_sha)"
assert_equals "record: session_token" "${_TOK}" "$(_lastf .session_token)"
assert_equals "record: transcript pointer" "${_TPATH}" "$(_lastf .transcript_path)"
assert_equals "record: material_source is TRUE for a source change" "true" "$(_lastf .material_source)"
assert_equals "record: log is 0600" "-rw-------" "$(ls -l "${_VLOG}" | cut -c1-10)"
_rid="$(_lastf .record_id)"
case "${_rid}" in
    ''|null) _record_fail "record: record_id present" "got '${_rid}'" ;;
    *)       _record_pass "record: record_id present" ;;
esac
assert_not_contains "record: raw command text is never written" "git push" "$(cat "${_VLOG}")"

# --- A credential embedded in the origin URL must not reach the corpus -----
git -C "${RB}" remote set-url origin "https://user:s3cr3t@example.invalid/org/b.git"
rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RB}" "git push origin HEAD" >/dev/null
assert_not_contains "record: URL userinfo is stripped" "s3cr3t" "$(cat "${_VLOG}" 2>/dev/null)"
assert_equals       "record: repo_id survives the strip" "example.invalid/org/b" "$(_lastf .repo_id)"
git -C "${RB}" remote set-url origin "https://example.invalid/org/b.git"

# --- The record names the SUBJECT, not the session checkout (#219) ---------
# `.repo` is the one field the ROOT alone determines: worktrees share refs, so
# branch and head_sha come out right whichever root is passed.
rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA_WT}" "git -C ${RA} push origin feat" >/dev/null
assert_equals "subject: record names the pushed tree, not the session cwd" "${RA}" "$(_lastf .repo)"
assert_equals "subject: record names the pushed branch" "feat" "$(_lastf .branch)"

# ---------------------------------------------------------------------------
# 3. Population: who is NOT in the corpus
# ---------------------------------------------------------------------------
# Status NOT satisfied is a different failure (the existing deny), and must not
# enter this leg's denominator.
rm -f "${_VLOG}" "${_ART}"; _seed_status '["requesting-code-review"]'
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_contains "status unsatisfied still DENIES (existing leg untouched)" '"deny"' "${out:-<empty>}"
assert_equals   "status unsatisfied => no shadow record" "0" "$(_nrec)"

# Milestone not in the chain: the leg has no claim to make.
rm -f "${_VLOG}"
jq -nc '{chain:["requesting-code-review"], completed:["requesting-code-review"]}' \
    > "${HOME}/.claude/.skill-composition-state-${_TOK}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals   "milestone not in chain => no shadow record" "0" "$(_nrec)"

# A pure ref deletion ships no content, so there is nothing to have verified.
rm -f "${_VLOG}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git push --delete origin scratch" >/dev/null
assert_equals   "deletion-only push => no shadow record" "0" "$(_nrec)"
# ...and the control: the same state with a content-bearing push DOES record,
# so the cell above is not passing on a guard that simply never fires.
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals   "control: content-bearing push in the same state records" "1" "$(_nrec)"

# A merge is outside the population: the verdict binds a branch-local commit
# and a merge's subject is the PR.
rm -f "${_VLOG}"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "gh pr merge 5 --squash")"
assert_equals       "gh pr merge => no shadow record" "0" "$(_nrec)"
assert_not_contains "gh pr merge => no VERIFY VERDICT advisory" "VERIFY VERDICT" "${out:-}"

# Not a push at all.
rm -f "${_VLOG}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git status" >/dev/null
assert_equals   "non-push command => no shadow record" "0" "$(_nrec)"

# ---------------------------------------------------------------------------
# 4. Fail-open and non-interference, in a COPY of the plugin tree.
#    The copy's unmodified output is asserted identical to the real tree's
#    first, so a difference below is the injected fault and not the copy.
# ---------------------------------------------------------------------------
PLUG="${TMP}/plug"; mkdir -p "${PLUG}"
cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/config" "${PROJECT_ROOT}/scripts" "${PLUG}/" 2>/dev/null
mkdir -p "${PLUG}/skills/project-verification"
cp -R "${PROJECT_ROOT}/skills/project-verification/scripts" "${PLUG}/skills/project-verification/" 2>/dev/null

rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
_real_out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
rm -f "${_VLOG}"
_copy_out="$(_guard "${PLUG}" "${RA}" "git push origin HEAD")"
assert_equals "positive control: plugin copy behaves like the real tree" "${_real_out}" "${_copy_out}"
assert_equals "positive control: plugin copy records" "1" "$(_nrec)"

# Recorder absent: the advisory is unchanged and nothing is recorded.
mv "${PLUG}/hooks/lib/verify-shadow.sh" "${PLUG}/hooks/lib/verify-shadow.sh.hidden"
rm -f "${_VLOG}"
_norec_out="$(_guard "${PLUG}" "${RA}" "git push origin HEAD")"
assert_equals       "recorder absent => guard output byte-identical" "${_copy_out}" "${_norec_out}"
assert_equals       "recorder absent => nothing recorded" "0" "$(_nrec)"
mv "${PLUG}/hooks/lib/verify-shadow.sh.hidden" "${PLUG}/hooks/lib/verify-shadow.sh"

# Recorder that FAILS mid-source: still no deny, still an allow-shaped output.
cp "${PLUG}/hooks/lib/verify-shadow.sh" "${PLUG}/hooks/lib/verify-shadow.sh.orig"
printf 'false\nreturn 1\n' > "${PLUG}/hooks/lib/verify-shadow.sh"
rm -f "${_VLOG}"
_bad_out="$(_guard "${PLUG}" "${RA}" "git push origin HEAD")"
assert_equals       "recorder faulting => guard output byte-identical" "${_copy_out}" "${_bad_out}"
mv "${PLUG}/hooks/lib/verify-shadow.sh.orig" "${PLUG}/hooks/lib/verify-shadow.sh"

# The leg never changes a DENY. Status unsatisfied, with and without the
# recorder, must produce the identical deny.
_seed_status '["requesting-code-review"]'
_deny_with="$(_guard "${PLUG}" "${RA}" "git push origin HEAD")"
mv "${PLUG}/hooks/lib/verify-shadow.sh" "${PLUG}/hooks/lib/verify-shadow.sh.hidden"
_deny_without="$(_guard "${PLUG}" "${RA}" "git push origin HEAD")"
mv "${PLUG}/hooks/lib/verify-shadow.sh.hidden" "${PLUG}/hooks/lib/verify-shadow.sh"
assert_contains "deny path still denies" '"deny"' "${_deny_with:-<empty>}"
assert_equals   "deny text is untouched by the leg" "${_deny_with}" "${_deny_without}"

# MUTATION: make the predicate accept a hand-authored rung. The S2 cell must
# flip to "no record" — which proves the e2e cells read the lib's predicate
# rather than passing on some neighbouring mechanism.
cp "${PLUG}/hooks/lib/verdict.sh" "${PLUG}/hooks/lib/verdict.sh.orig"
sed 's/verify-yml|explicit)/verify-yml|explicit|claude-md-commands)/' \
    "${PLUG}/hooks/lib/verdict.sh.orig" > "${PLUG}/hooks/lib/verdict.sh"
if cmp -s "${PLUG}/hooks/lib/verdict.sh.orig" "${PLUG}/hooks/lib/verdict.sh"; then
    _record_fail "mutation applied to the predicate" "sed changed nothing — the cell below would be vacuous"
else
    _record_pass "mutation applied to the predicate"
fi
rm -f "${_VLOG}"; _handwrite "${RA}" "claude-md-commands"; _seed_status "${_BOTH}"
_guard "${PLUG}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "MUTANT accepts the hand-authored rung (so the real predicate is load-bearing)" "0" "$(_nrec)"
mv "${PLUG}/hooks/lib/verdict.sh.orig" "${PLUG}/hooks/lib/verdict.sh"
rm -f "${_VLOG}"
_guard "${PLUG}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "restored predicate records it again" "1" "$(_nrec)"

# ---------------------------------------------------------------------------
# 4b. Cells added after independent review (2026-10-02). Every one of these
#     corresponds to a single-fault mutation that left the file green.
# ---------------------------------------------------------------------------

# --- each advisory arm says its own thing -----------------------------------
rm -f "${_VLOG}" "${_ART}"; _produce "${RA}"; _seed_status "${_BOTH}"
jq -c '.sha = "0000000000000000000000000000000000000000"' "${_ART}" > "${_ART}.t" && mv "${_ART}.t" "${_ART}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_equals       "unbound arm: reason" "unbound" "$(_lastf .reason)"
assert_contains     "unbound arm: says the verdict does not cover the commit" "does not cover this commit" "${out:-<empty>}"
assert_not_contains "unbound arm: does not claim no verdict exists" "no verification verdict covers" "${out:-}"

# A gate that could not run is could_not_verify: not clean, but not a failure,
# so verify-hardening does not deny and this leg's advisory is visible.
rm -f "${_VLOG}" "${_ART}"; _produce "${RB}" --name tests --run no-such-command-vmv; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RB}" "git push origin HEAD")"
assert_equals       "not-clean arm: reason" "not-clean" "$(_lastf .reason)"
assert_contains     "not-clean arm: says the verdict is not clean" "is not clean" "${out:-<empty>}"
assert_not_contains "not-clean arm: never denies" '"deny"' "${out:-}"

# --- the artifact must be exactly ONE document ------------------------------
_handwrite "${RA}" "claude-md-commands"
{ printf '{}\n'; cat "${_ART}"; } > "${_ART}.t" && mv "${_ART}.t" "${_ART}"
assert_equals "two-document artifact => cannot_check, not explained_ladder" \
    "cannot_check unparseable" "$(verdict_measured_class "${_TOK}" "${RA}")"

# --- a capitalised manifest name survives the sanitiser ---------------------
rm -f "${_VLOG}"; _handwrite "${RA}" "heuristic:Makefile"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "discovery_source 'heuristic:Makefile' is recorded verbatim" "heuristic:Makefile" "$(_lastf .discovery_source)"
rm -f "${_VLOG}"; _handwrite "${RA}" 'x"; rm -rf / #'; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "free-text discovery_source is reduced to a marker" "other" "$(_lastf .discovery_source)"

# --- SUBJECT REV: the commit asked about is the one the command pushes ------
# cwd has `feat` checked out and a MEASURED verdict at feat's HEAD. The command
# pushes `other` (= main's commit), which that verdict does not cover. Reading
# HEAD instead of the subject rev would find the verdict and stay silent.
rm -f "${_VLOG}" "${_ART}"; _produce "${RA}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin other" >/dev/null
assert_equals "subject rev: pushing an uncovered ref records" "1" "$(_nrec)"
assert_equals "subject rev: classified against the pushed ref" "unbound" "$(_lastf .reason)"
assert_equals "subject rev: head_sha is the PUSHED commit" "$(git -C "${RA}" rev-parse other)" "$(_lastf .head_sha)"
assert_equals "subject rev: branch is the PUSHED branch" "other" "$(_lastf .branch)"

# --- SUBJECT ROOT at the classifier: the session sits in another worktree ----
# Same measured verdict at RA's HEAD. From RA_WT (HEAD = main's commit), a
# `git -C RA push` must be judged against RA's HEAD and stay silent.
# RA then gains a commit, so the verdict covers its HEAD only as an own-token
# ANCESTOR: the exact-commit sibling scan cannot rescue a classifier handed the
# wrong root, which is what would otherwise make this cell pass regardless.
( cd "${RA}" && echo "# c2" >> run.sh && git commit -qam c2 ) >/dev/null 2>&1
rm -f "${_VLOG}"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RA_WT}" "git -C ${RA} push origin HEAD")"
assert_equals       "subject root: verdict judged against the pushed tree => no record" "0" "$(_nrec)"
assert_not_contains "subject root: no advisory" "VERIFY VERDICT" "${out:-}"

# --- a MEASURED verdict under another token at the same commit --------------
# verdict_resolve_token does not rank by provenance, so an own hand-authored
# verdict used to shadow a sibling's measurement of the very same commit.
rm -f "${_VLOG}"; _handwrite "${RA}" "claude-md-commands"; _seed_status "${_BOTH}"
( cd "${RA}" && SKILL_SESSION_TOKEN="session-sib" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    /bin/bash "${PRODUCER}" < /dev/null ) >/dev/null 2>&1
_SIB="${HOME}/.claude/.skill-project-verified-session-sib"
assert_file_exists "sibling measured verdict produced by the REAL writer" "${_SIB}"
out="$(_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD")"
assert_equals       "sibling measured at the same commit => no record" "0" "$(_nrec)"
assert_not_contains "sibling measured at the same commit => no advisory" "VERIFY VERDICT" "${out:-}"
# Control: the sibling bound to a DIFFERENT commit must not rescue it — even
# when this commit's sha appears elsewhere in the file. The scan prefilters
# with `grep -lF <sha>`, which matches ANY field, so only the jq-confirmed
# `.sha` comparison stands between a mention and a binding.
jq -c --arg h "$(_head "${RA}")" '.sha = "0000000000000000000000000000000000000000" | .output_excerpt = ("ran at " + $h)' \
    "${_SIB}" > "${_SIB}.t" && mv "${_SIB}.t" "${_SIB}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "control: sibling at another commit does not rescue" "explained_ladder" "$(_lastf .classification)"
# A two-document sibling: a measured FAILING verdict followed by a stray clean
# object. Read unslurped, jq reports on the LAST value and it looks clean.
( cd "${RA}" && SKILL_SESSION_TOKEN="session-sib" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    /bin/bash "${PRODUCER}" < /dev/null ) >/dev/null 2>&1
jq -c '.failed = ["tests"] | .passed = []' "${_SIB}" > "${_SIB}.t"
printf '{"gate_gaming_status":"clean"}\n' >> "${_SIB}.t"; mv "${_SIB}.t" "${_SIB}"
rm -f "${_VLOG}"; _handwrite "${RA}" "claude-md-commands"; _seed_status "${_BOTH}"
assert_equals "two-document sibling is not a measured verdict" "1" \
    "$(_bool verdict_any_measured_at_head "${RA}")"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "two-document sibling does not silence the leg" "explained_ladder" "$(_lastf .classification)"
rm -f "${_SIB}"

# Own verdict NOT CLEAN at this commit, sibling measured and clean at the same
# commit: the recorded failure is not erased (the resolver is deny-biased, and
# this leg follows it).
rm -f "${_VLOG}" "${_ART}"; _produce "${RA}"
jq -c '.could_not_verify = ["types"]' "${_ART}" > "${_ART}.t" && mv "${_ART}.t" "${_ART}"
( cd "${RA}" && SKILL_SESSION_TOKEN="session-sib" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    /bin/bash "${PRODUCER}" < /dev/null ) >/dev/null 2>&1
_seed_status "${_BOTH}"
assert_equals "control: the sibling alone WOULD satisfy the scan" "0" \
    "$(_bool verdict_any_measured_at_head "${RA}")"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
assert_equals "own not-clean + sibling clean: still recorded" "1" "$(_nrec)"
assert_equals "own not-clean + sibling clean: reason not-clean" "not-clean" "$(_lastf .reason)"
rm -f "${_SIB}"

# --- verdict.sh ABSENT: recorded as cannot_check, announced once, not twice --
mv "${PLUG}/hooks/lib/verdict.sh" "${PLUG}/hooks/lib/verdict.sh.hidden"
rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
out="$(_guard "${PLUG}" "${RA}" "git push origin HEAD")"
assert_equals       "verdict.sh absent => recorded" "1" "$(_nrec)"
assert_equals       "verdict.sh absent => cannot_check" "cannot_check" "$(_lastf .classification)"
assert_equals       "verdict.sh absent => reason lib-unavailable" "lib-unavailable" "$(_lastf .reason)"
assert_equals       "verdict.sh absent => material_source is null, not false" "null" "$(_lastf .material_source)"
assert_not_contains "verdict.sh absent => no second advisory from this leg" "VERIFY VERDICT" "${out:-}"
assert_contains     "verdict.sh absent => the degradation note carries it" "verdict.sh did not load" "${out:-<empty>}"
assert_not_contains "verdict.sh absent => never denies" '"deny"' "${out:-}"
mv "${PLUG}/hooks/lib/verdict.sh.hidden" "${PLUG}/hooks/lib/verdict.sh"

# --- verdict.sh present but PREDATING this reader ---------------------------
cp "${PLUG}/hooks/lib/verdict.sh" "${PLUG}/hooks/lib/verdict.sh.orig"
awk '/^# --- Measured provenance \(#301\)/ { skip = 1 } /^# verdict_test_delta / { skip = 0 } !skip' \
    "${PLUG}/hooks/lib/verdict.sh.orig" > "${PLUG}/hooks/lib/verdict.sh"
if grep -q 'verdict_measured_class()' "${PLUG}/hooks/lib/verdict.sh"; then
    _record_fail "older verdict.sh fixture lacks the new reader" "the strip matched nothing — the cells below would be vacuous"
else
    _record_pass "older verdict.sh fixture lacks the new reader"
fi
rm -f "${_VLOG}"
out="$(_guard "${PLUG}" "${RA}" "git push origin HEAD")"
assert_equals   "older verdict.sh => reason reader-unavailable" "reader-unavailable" "$(_lastf .reason)"
assert_contains "older verdict.sh => says it could not check" "could not check" "${out:-<empty>}"
mv "${PLUG}/hooks/lib/verdict.sh.orig" "${PLUG}/hooks/lib/verdict.sh"

# --- NON-INTERFERENCE with a deny BELOW the leg ------------------------------
# The earlier "deny text is untouched" cell used the STATUS deny, which exits
# before this leg is reached, so it pinned nothing. These two drive denies that
# fire AFTER the leg has run and compare against a copy with the leg disabled:
# an early exit, a changed deny text, or a swallowed deny all show as a diff.
PLUG_OFF="${TMP}/plug-off"; cp -R "${PLUG}" "${PLUG_OFF}"
sed 's/^               \[ "\${_vm_gate}" != "non-local" \]; then$/               false; then/' \
    "${PLUG}/hooks/openspec-guard.sh" > "${PLUG_OFF}/hooks/openspec-guard.sh"
if cmp -s "${PLUG}/hooks/openspec-guard.sh" "${PLUG_OFF}/hooks/openspec-guard.sh"; then
    _record_fail "leg disabled in the control copy" "sed changed nothing — the comparisons below would be vacuous"
else
    _record_pass "leg disabled in the control copy"
fi

# (a) verify-hardening: a MEASURED, FAILING verdict at HEAD.
rm -f "${_VLOG}" "${_ART}"; _produce "${RB}" --name tests --run false; _seed_status "${_BOTH}"
_on="$(_guard "${PLUG}" "${RB}" "git push origin HEAD")"
_n_on="$(_nrec)"; _r_on="$(_lastf .reason)"
rm -f "${_VLOG}"
_off="$(_guard "${PLUG_OFF}" "${RB}" "git push origin HEAD")"
assert_contains "deny below (verify-hardening): still denies" '"deny"' "${_on:-<empty>}"
assert_equals   "deny below (verify-hardening): output identical with the leg off" "${_off}" "${_on}"
assert_equals   "deny below (verify-hardening): the leg DID fire" "not-clean" "${_r_on}"
assert_equals   "deny below (verify-hardening): recorded ONCE, not again by the capture replay" "1" "${_n_on}"
assert_equals   "control: the disabled copy records nothing" "0" "$(_nrec)"

# (b) routing-governance: a routing repo, no verdict at all.
RR="${TMP}/rr"; mkdir -p "${RR}"
(
  cd "${RR}" || exit 1
  git -c init.defaultBranch=main init -q
  git config user.email t@t; git config user.name t
  git remote add origin "https://example.invalid/org/r.git"
  mkdir -p config hooks
  echo '{}' > config/default-triggers.json
  printf '#!/bin/bash\n' > hooks/x.sh
  git add -A; git commit -qm base
  git checkout -qb feat
  echo "# c1" >> hooks/x.sh; git commit -qam c1
) >/dev/null 2>&1
rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
_on="$(_guard "${PLUG}" "${RR}" "git push origin HEAD")"
_n_on="$(_nrec)"; _r_on="$(_lastf .reason)"
rm -f "${_VLOG}"
_off="$(_guard "${PLUG_OFF}" "${RR}" "git push origin HEAD")"
assert_contains "deny below (routing-governance): still denies" '"deny"' "${_on:-<empty>}"
assert_equals   "deny below (routing-governance): output identical with the leg off" "${_off}" "${_on}"
assert_equals   "deny below (routing-governance): the leg DID fire" "absent" "${_r_on}"
assert_equals   "deny below (routing-governance): recorded once" "1" "${_n_on}"

# --- repository identity -----------------------------------------------------
# One repository reached through three URL spellings, and two credential shapes.
_RIDLOG="${TMP}/rid.jsonl"
while IFS= read -r _url; do
    [ -n "${_url}" ] || continue
    git -C "${RA}" remote set-url origin "${_url}"
    rm -f "${_RIDLOG}"
    VERIFY_SHADOW_LOG="${_RIDLOG}" verify_shadow_record tok "${RA}" unexplained absent push HEAD "" false ""
    assert_equals "repo_id of '${_url%%SEKRET*}' normalises to host/path" \
        "example.invalid/org/a" "$(jq -r .repo_id "${_RIDLOG}" 2>/dev/null)"
    assert_not_contains "repo_id of that URL carries no credential" "SEKRET" "$(cat "${_RIDLOG}" 2>/dev/null)"
done <<EOF
https://example.invalid/org/a.git
git@example.invalid:org/a.git
https://example.invalid/org/a
ssh://git@example.invalid/org/a.git/
https://user:SEKRET@example.invalid/org/a.git
https://user:SEKRET@x@example.invalid/org/a.git
https://example.invalid/org/a.git?private_token=SEKRET
https://user:pa/SEKRET@example.invalid/org/a.git
https://user:SEK#SEKRET@example.invalid/org/a.git
ssh://git@example.invalid:2222/org/a.git
https://EXAMPLE.Invalid/org/a.git
git@example.invalid:/org/a.git
EOF
git -C "${RA}" remote set-url origin "https://example.invalid/org/a.git"

# An owner whose name starts with a DIGIT. scp syntax has no port, so the ":"
# is always the path separator; sparing "digits after the colon" as a port
# split this one repository in two, in the direction that makes clause 4 easier.
assert_equals "digit-leading owner: https form" "github.invalid/11ty/eleventy" \
    "$(_verify_shadow_repo_id "https://github.invalid/11ty/eleventy.git")"
assert_equals "digit-leading owner: scp form is the SAME identity" "github.invalid/11ty/eleventy" \
    "$(_verify_shadow_repo_id "git@github.invalid:11ty/eleventy.git")"
assert_equals "a local path is left as a path" "/srv/git/r" "$(_verify_shadow_repo_id "/srv/git/r.git")"
assert_equals "file:// and the bare path agree" "/srv/git/r" "$(_verify_shadow_repo_id "file:///srv/git/r.git")"

# No origin at all: a repo and its worktree still share ONE identity.
RN="${TMP}/rn"; mkdir -p "${RN}"
( cd "${RN}" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t \
    && echo a > a && git add -A && git commit -qm base && git worktree add -q -b w2 "${TMP}/rn-wt" main ) >/dev/null 2>&1
rm -f "${_RIDLOG}"
VERIFY_SHADOW_LOG="${_RIDLOG}" verify_shadow_record tok "${RN}" unexplained absent push HEAD "" false ""
VERIFY_SHADOW_LOG="${_RIDLOG}" verify_shadow_record tok "${TMP}/rn-wt" unexplained absent push HEAD "" false ""
_ids="$(jq -r .repo_id "${_RIDLOG}" 2>/dev/null | LC_ALL=C sort -u | grep -c . | tr -d '[:space:]')"
assert_equals    "no origin: repo and its worktree share one repo_id" "1" "${_ids}"
assert_not_empty "no origin: repo_id is not empty" "$(jq -r .repo_id "${_RIDLOG}" 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# 4c. Scope (predicate_version 2): a repo that DECLARES a non-local substrate
#     is out of the leg. The writer refuses to run there by any route, so no
#     measured verdict can exist and the remedy this leg names could not be
#     executed.
# ---------------------------------------------------------------------------
assert_equals "gate declaration: declared local"  "local"  "$(verdict_gate_declaration "${RA}")"
assert_equals "gate declaration: nothing declared" "absent" "$(verdict_gate_declaration "${RB}")"
assert_equals "gate declaration: unresolvable commit" "unknown" "$(verdict_gate_declaration "${RA}" "no-such-ref")"
RNL="${TMP}/rnl"; mkdir -p "${RNL}"
(
  cd "${RNL}" || exit 1
  git -c init.defaultBranch=main init -q
  git config user.email t@t; git config user.name t
  git remote add origin "https://example.invalid/org/nl.git"
  printf 'substrate: ci\ncommands:\n  - name: tests\n    run: true\n' > .verify.yml
  printf '#!/bin/bash\n' > run.sh
  git add -A; git commit -qm base
  git checkout -qb feat
  echo "# c1" >> run.sh; git commit -qam c1
) >/dev/null 2>&1
assert_equals "gate declaration: declared non-local" "non-local" "$(verdict_gate_declaration "${RNL}")"
# The REAL writer agrees that nothing can be measured there — the premise.
rm -f "${_ART}"; _produce "${RNL}"; _produce "${RNL}" --name tests --run true
if [ -f "${_ART}" ]; then _record_fail "premise: the writer produces no verdict in a non-local repo" "it wrote one — the scope exclusion is unjustified"
else _record_pass "premise: the writer produces no verdict in a non-local repo, by either route"; fi
rm -f "${_VLOG}"; _seed_status "${_BOTH}"
out="$(_guard "${PROJECT_ROOT}" "${RNL}" "git push origin HEAD")"
assert_equals       "non-local substrate => no shadow record" "0" "$(_nrec)"
assert_not_contains "non-local substrate => no VERIFY VERDICT advisory" "VERIFY VERDICT" "${out:-}"
# Control: the SAME repo declared local, same state, DOES record — so the cell
# above is the scope rule and not a leg that failed to fire.
( cd "${RNL}" && printf 'substrate: local\ncommands:\n  - name: tests\n    run: true\n' > .verify.yml && git commit -qam local ) >/dev/null 2>&1
_guard "${PROJECT_ROOT}" "${RNL}" "git push origin HEAD" >/dev/null
assert_equals "control: the same repo declared local records" "1" "$(_nrec)"
# The declaration is read from the PUSHED commit, not the working tree.
( cd "${RNL}" && printf 'substrate: ci\n' > .verify.yml ) >/dev/null 2>&1
rm -f "${_VLOG}"
_guard "${PROJECT_ROOT}" "${RNL}" "git push origin HEAD" >/dev/null
assert_equals "an UNCOMMITTED edit to the declaration does not change scope" "1" "$(_nrec)"
# A repo declaring nothing is IN scope and says so in the record.
rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RB}" "git push origin HEAD" >/dev/null
assert_equals "no declaration: in scope, recorded as absent" "absent" "$(_lastf .gate_declaration)"

# ---------------------------------------------------------------------------
# 5. Static posture
# ---------------------------------------------------------------------------
_enf="$(grep '^_GATE_ENFORCE_LIBS=' "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null)"
assert_not_empty    "found _GATE_ENFORCE_LIBS (non-vacuity)" "${_enf}"
assert_not_contains "verify-shadow.sh is diagnostic: NOT in _GATE_ENFORCE_LIBS" "verify-shadow.sh" "${_enf}"
assert_contains     "verdict.sh (the predicate's home) IS in _GATE_ENFORCE_LIBS" "hooks/lib/verdict.sh" "${_enf}"
assert_equals "the guard never reads the adjudicator" "0" \
    "$(grep -c 'verify-shadow-adjudicate' "${GUARD}" | tr -d '[:space:]')"
assert_equals "the reader emits no permissionDecision" "0" \
    "$(grep -c 'permissionDecision' "${READER}" | tr -d '[:space:]')"
# The call site must pass the SUBJECT root in argument position 2 — matched as
# an argument, never as a substring of a neighbourhood (a trailing comment
# naming the variable would satisfy a window grep).
_site="$(grep -o 'verify_shadow_record "\${_SESSION_TOKEN}" "\${[A-Za-z_]*}"' "${GUARD}" | head -1)"
assert_equals "guard passes _SUBJ_ROOT as the recorder's root argument" \
    'verify_shadow_record "${_SESSION_TOKEN}" "${_SUBJ_ROOT}"' "${_site}"

# ---------------------------------------------------------------------------
# 6. The reader, under the 2026-10-02 re-registration (predicate_version 2).
#    Corpora come from the REAL recorder; only ts is patched. Labels come from
#    the REAL --adjudicate, never a hand-written sidecar row, except where a
#    cell is about a corrupt sidecar.
# ---------------------------------------------------------------------------
_CORP="${TMP}/corpus.jsonl"
_ADJ="${TMP}/adjudication.jsonl"
_emit() { # <repo> <class> <reason> <token> <ts>
    VERIFY_SHADOW_LOG="${_CORP}" verify_shadow_record "$4" "$1" "$2" "$3" push HEAD "" false "" local
    local _l; _l="$(tail -1 "${_CORP}")"
    sed '$d' "${_CORP}" > "${_CORP}.t"
    printf '%s\n' "${_l}" | jq -c --arg ts "$5" '.ts = $ts' >> "${_CORP}.t"
    mv "${_CORP}.t" "${_CORP}"
}
_rd() { # <now> <args...>  — the reader as a HUMAN would run it
    local _now="$1"; shift
    env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID \
        VERIFY_SHADOW_LOG="${_CORP}" VERIFY_ADJUDICATION_LOG="${_ADJ}" VERIFY_SHADOW_NOW="${_now}" \
        /bin/bash "${READER}" "$@" 2>&1
}
_status() { _rd "${1:-2026-10-20T00:00:00Z}" --status; }
_label()  { # <record_id> <verdict> [now]
    _rd "${3:-2026-10-19T00:00:00Z}" --adjudicate "$1" --verdict "$2" --reason test >/dev/null
}
_label_agent() { # <record_id> <verdict>
    CLAUDECODE=1 VERIFY_SHADOW_LOG="${_CORP}" VERIFY_ADJUDICATION_LOG="${_ADJ}" \
        VERIFY_SHADOW_NOW="2026-10-19T00:00:00Z" /bin/bash "${READER}" --adjudicate "$1" --verdict "$2" >/dev/null 2>&1
}
_label_all() { # <verdict>  — one human label per would-block record
    local _id
    while IFS= read -r _id; do
        [ -n "${_id}" ] || continue
        _label "${_id}" "$1"
    done <<EOF
$(jq -r 'select(.would_block == true) | .record_id' "${_CORP}" 2>/dev/null)
EOF
}
_rid() { sed -n "${1}p" "${_CORP}" | jq -r .record_id; }   # record id on line N
_reset() { rm -f "${_CORP}" "${_ADJ}"; }

# --- the floor comes from the SHARED band rule, not from a number typed here --
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/shadow-corpus.sh"
assert_equals "shared rule: zero false blocks of 29 is DENY (<10% at 95%)" "DENY" \
    "$(ALPHA=0.05 DENY_P=0.10 ADVISORY_P=0.20 shadow_band 0 29)"
if [ "$(ALPHA=0.05 DENY_P=0.10 ADVISORY_P=0.20 shadow_band 0 28)" != "DENY" ]; then
    _record_pass "shared rule: zero false blocks of 28 is NOT yet DENY (so the floor is 29, not lower)"
else
    _record_fail "shared rule: zero false blocks of 28 is NOT yet DENY" "the floor would be lower than registered"
fi
assert_contains "reader takes its band from the shared lib" "shadow_band" "$(cat "${READER}")"

# --- no corpus is reported as no corpus --------------------------------------
_reset
out="$(_status)"
assert_contains "no corpus is reported as no corpus" "no corpus yet" "${out}"
assert_contains "no corpus => decision rule not met" "DECISION RULE NOT MET" "${out}"
assert_contains "no corpus => --next has nothing outstanding" "nothing outstanding" "$(_rd 2026-10-20T00:00:00Z --next)"

# --- round trip: REAL guard -> REAL reader -> REAL label ----------------------
# ts is patched to a fixed in-window instant: a record stamped with the real
# clock would start failing this cell the day the registered deadline passes.
rm -f "${_VLOG}" "${_ART}" "${_ADJ}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
jq -c '.ts = "2026-10-05T10:00:00Z"' "${_VLOG}" > "${_CORP}"
out="$(_status)"
assert_contains "round trip: guard-written record is one would-block episode" "n=1" "${out}"
assert_contains "round trip: it starts unresolved" "unresolved=1" "${out}"
out="$(_rd 2026-10-20T00:00:00Z --next)"
assert_contains "round trip: --next offers that episode" "$(_rid 1)" "${out}"
assert_contains "round trip: --next shows the recorded gate declaration" "gate=local" "${out}"
assert_contains "round trip: --next states what a false block is" "FALSE BLOCK" "${out}"
_before="$(cksum < "${_CORP}")"
_label "$(_rid 1)" true_catch
assert_equals   "labelling never mutates the shadow log" "${_before}" "$(cksum < "${_CORP}")"
assert_equals   "sidecar is 0600" "-rw-------" "$(ls -l "${_ADJ}" | cut -c1-10)"
out="$(_status)"
assert_contains "round trip: a human label resolves it" "true_catch=1" "${out}"
assert_contains "round trip: nothing unresolved" "unresolved=0" "${out}"
assert_contains "round trip: --next says everything is labelled" "carries a human label" \
    "$(_rd 2026-10-20T00:00:00Z --next)"

# --- an AGENT's label resolves nothing ---------------------------------------
_reset
_emit "${RA}" unexplained absent t1 "2026-10-05T10:00:00Z"
_label_agent "$(_rid 1)" true_catch
out="$(_status)"
assert_contains "agent label: episode stays unresolved" "unresolved=1" "${out}"
assert_contains "agent label: reported as ignored" "agent-claimed row(s) ignored" "${out}"

# --- episode grouping: anchored 30 minutes, same (repo, branch, token) -------
_reset
_emit "${RA}" unexplained absent tok1 "2026-10-05T10:00:00Z"
_emit "${RA}" unexplained absent tok1 "2026-10-05T10:20:00Z"   # +20m: same episode
_emit "${RA}" unexplained absent tok1 "2026-10-05T10:40:00Z"   # +40m from ANCHOR: new episode
out="$(_status)"
assert_contains "three records, anchored window => two episodes" "n=2" "${out}"
assert_contains "record count is reported separately from n" "3 line(s)" "${out}"
# One label covers the whole episode, and only that episode.
_label "$(_rid 2)" true_catch
out="$(_status)"
assert_contains "one label covers both records of its episode" "true_catch=1" "${out}"
assert_contains "the other episode is still unresolved" "unresolved=1" "${out}"

# --- a record joining a labelled episode UNRESOLVES it -----------------------
_reset
_emit "${RA}" unexplained absent tok1 "2026-10-05T10:00:00Z"
_label "$(_rid 1)" true_catch
_emit "${RA}" unexplained not-clean tok1 "2026-10-05T10:10:00Z"
out="$(_status)"
assert_contains "new evidence in a labelled episode => unresolved again" "unresolved=1" "${out}"

# --- cannot_check is reported and NEVER counted (owner ruling 2) --------------
# The reviewer's reproduction: four cannot_check episodes in one repo plus one
# would-block in a second used to read "rule met".
_reset
_emit "${RA}" cannot_check unparseable t1 "2026-10-05T10:00:00Z"
_emit "${RA}" cannot_check unparseable t2 "2026-10-06T10:00:00Z"
_emit "${RA}" cannot_check unparseable t3 "2026-10-07T10:00:00Z"
_emit "${RA}" cannot_check unparseable t4 "2026-10-08T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t5 "2026-10-09T10:00:00Z"
_label "$(_rid 5)" true_catch
out="$(_status)"
assert_contains "cannot_check episodes do not count toward n" "n=1" "${out}"
assert_contains "cannot_check episodes are still reported" "cannot_check=4" "${out}"
assert_contains "a cannot_check-only repo adds no diversity" "repos=1" "${out}"
# A cannot_check-only episode cannot be labelled into the count.
_rd 2026-10-20T00:00:00Z --adjudicate "$(_rid 1)" --verdict true_catch >/dev/null 2>&1
assert_equals "labelling a cannot_check-only episode is refused" "1" "$?"
# In a MIXED episode the cannot_check record neither qualifies nor blocks.
_reset
_emit "${RA}" cannot_check unparseable t1 "2026-10-05T10:00:00Z"
_emit "${RA}" unexplained absent       t1 "2026-10-05T10:05:00Z"
_label "$(_rid 2)" true_catch
out="$(_status)"
assert_contains "mixed episode counts once" "n=1" "${out}"
assert_contains "mixed episode resolves on its would-block record alone" "true_catch=1" "${out}"

# --- the rule: 29 would-block episodes, all human true catches, two repos -----
# Built once and copied. HALF are `unexplained` — the leg's own true catches —
# which under the superseded rule each held the flip (owner ruling 1).
_reset
_i=0
while [ "${_i}" -lt 29 ]; do
    _i=$(( _i + 1 ))
    _mm="$(printf '%02d' "${_i}")"
    if [ $(( _i % 2 )) -eq 0 ]; then _r="${RA}"; _c="unexplained"; _why="absent"
    else _r="${RB}"; _c="explained_ladder"; _why="hand-authored"; fi
    _emit "${_r}" "${_c}" "${_why}" "s${_i}" "2026-10-05T10:${_mm}:00Z"
done
cp "${_CORP}" "${TMP}/base29.jsonl"
_base() { cp "${TMP}/base29.jsonl" "${_CORP}"; rm -f "${_ADJ}"; [ -f "${TMP}/base29.adj" ] && cp "${TMP}/base29.adj" "${_ADJ}"; }

out="$(_status)"
assert_contains "29 unlabelled episodes: clause 1 met" "[MET] 1." "${out}"
assert_contains "29 unlabelled episodes: clause 3 UNMET" "[UNMET] 3." "${out}"
assert_contains "29 unlabelled episodes: rule not met — silence clears nothing" "DECISION RULE NOT MET" "${out}"

_label_all true_catch
cp "${_ADJ}" "${TMP}/base29.adj"
out="$(_status)"
assert_contains "all labelled: clause 1" "[MET] 1." "${out}"
assert_contains "all labelled: clause 2" "[MET] 2." "${out}"
assert_contains "all labelled: clause 3" "[MET] 3." "${out}"
assert_contains "all labelled: clause 4" "[MET] 4." "${out}"
assert_contains "all labelled: true catches of BOTH classes count" "true_catch=29" "${out}"
assert_contains "all labelled => rule met" "DECISION RULE MET" "${out}"
assert_contains "the reader authorises nothing by itself" "separate change" "${out}"
assert_contains "band agrees with the floor" "DENY" "${out}"

# 28 is below the floor.
_base; sed '$d' "${_CORP}" > "${_CORP}.t"; mv "${_CORP}.t" "${_CORP}"
out="$(_status)"
assert_contains "28 episodes => clause 1 unmet" "[UNMET] 1." "${out}"
assert_not_contains "28 episodes => never MET" "DECISION RULE MET" "${out}"

# One EXPLAINED episode left unlabelled: it is not a true catch "by construction".
_base; grep -v "\"record_id\":\"$(_rid 1)\"" "${_ADJ}" > "${_ADJ}.t"; mv "${_ADJ}.t" "${_ADJ}"
assert_equals "fixture: line 1 is an explained_ladder record" "explained_ladder" "$(sed -n 1p "${_CORP}" | jq -r .classification)"
out="$(_status)"
assert_contains "unlabelled explained_ladder episode => unresolved" "unresolved=1" "${out}"
assert_not_contains "unlabelled explained_ladder episode => never MET" "DECISION RULE MET" "${out}"

# `unknown` keeps an episode unresolved.
_base; _label "$(_rid 2)" unknown
out="$(_status)"
assert_contains "label unknown => unresolved" "unresolved=1" "${out}"
assert_not_contains "label unknown => never MET" "DECISION RULE MET" "${out}"

# One confirmed false block ends it for this predicate version.
_base; _label "$(_rid 2)" false_block
out="$(_status)"
assert_contains "false block: clause 2 unmet" "[UNMET] 2." "${out}"
assert_contains "false block: named as terminal" "FALSE BLOCK CONFIRMED" "${out}"
assert_not_contains "false block: never MET" "DECISION RULE MET" "${out}"
# An agent cannot displace a human's false_block.
_label_agent "$(_rid 2)" true_catch
out="$(_status)"
assert_contains "agent true_catch after human false_block: still a false block" "FALSE BLOCK CONFIRMED" "${out}"
# A human CORRECTION supersedes: the latest human label wins.
_label "$(_rid 2)" true_catch
out="$(_status)"
assert_contains "a human correction supersedes the earlier label" "DECISION RULE MET" "${out}"

# All 29 in ONE repository.
_reset
_i=0
while [ "${_i}" -lt 29 ]; do
    _i=$(( _i + 1 ))
    _emit "${RA}" unexplained absent "s${_i}" "2026-10-05T10:$(printf '%02d' "${_i}"):00Z"
done
_label_all true_catch
out="$(_status)"
assert_contains "one repository => clause 4 unmet" "[UNMET] 4." "${out}"
assert_not_contains "one repository => never MET" "DECISION RULE MET" "${out}"
# ...and a second repo present only as an UNLABELLED episode adds no diversity.
_emit "${RB}" unexplained absent sx "2026-10-06T10:00:00Z"
out="$(_status)"
assert_contains "an unlabelled episode in a second repo is not diversity" "repos=1" "${out}"

# Two worktrees of one repository, and three URL spellings of it, are one repo.
_reset
_emit "${RA}"    explained_ladder hand-authored tokA "2026-10-05T10:00:00Z"
_emit "${RA_WT}" explained_ladder hand-authored tokB "2026-10-06T10:00:00Z"
_label_all true_catch
assert_contains "two worktrees, one origin => 1 distinct repo" "repos=1" "$(_status)"
_reset
_i=0
while IFS= read -r _url; do
    [ -n "${_url}" ] || continue
    _i=$(( _i + 1 ))
    git -C "${RA}" remote set-url origin "${_url}"
    _emit "${RA}" explained_ladder hand-authored "u${_i}" "2026-10-0${_i}T10:00:00Z"
done <<EOF
https://example.invalid/org/a.git
git@example.invalid:org/a.git
https://example.invalid/org/a
EOF
git -C "${RA}" remote set-url origin "https://example.invalid/org/a.git"
_label_all true_catch
out="$(_status)"
assert_contains "three URL spellings of one repo => repos=1" "repos=1" "${out}"
assert_contains "three URL spellings: three episodes" "n=3" "${out}"

# --- deadlines ----------------------------------------------------------------
_reset
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t2 "2026-10-06T10:00:00Z"
_label_all true_catch
out="$(_status "2026-11-01T00:00:00Z")"
assert_contains "before 2026-12-31 the starvation check is open" "starvation check : OPEN" "${out}"
out="$(_status "2027-01-05T00:00:00Z")"
assert_contains "fewer than 3 by 2026-12-31 => null result" "NULL RESULT" "${out}"
_emit "${RB}" explained_ladder hand-authored t3 "2026-12-31T23:00:00Z"
_label "$(_rid 3)" true_catch
out="$(_status "2027-01-05T00:00:00Z")"
assert_contains "three by 2026-12-31 => starvation check cleared" "starvation check : CLEARED" "${out}"
assert_not_contains "cleared starvation check is not a null result" "NULL RESULT" "${out}"
# The FINAL deadline closes a window that 3..28 episodes would otherwise leave
# open for ever.
out="$(_status "2027-04-02T00:00:00Z")"
assert_contains "unmet at the final deadline => null result" "NULL RESULT" "${out}"
assert_contains "the final deadline is named" "2027-03-31" "${out}"
# A rule already MET stays met after the deadline: it was earned inside the window.
_base
out="$(_status "2027-04-02T00:00:00Z")"
assert_contains "met inside the window stays met after it" "DECISION RULE MET" "${out}"
# Episodes that BEGIN after the final deadline are never counted.
_base
sed -n '1,24p' "${_CORP}" > "${_CORP}.t"
sed -n '25,29p' "${_CORP}" | jq -c '.ts = "2027-04-01T10:00:00Z"' >> "${_CORP}.t"; mv "${_CORP}.t" "${_CORP}"
out="$(_status "2027-04-02T00:00:00Z")"
assert_contains "late episodes are not counted" "n=24" "${out}"
assert_contains "late episodes are reported" "5 episode(s) began after" "${out}"
assert_not_contains "late episodes cannot complete the floor" "DECISION RULE MET" "${out}"
# A label made AFTER the final deadline is ignored.
_base; grep -v "\"record_id\":\"$(_rid 3)\"" "${_ADJ}" > "${_ADJ}.t"; mv "${_ADJ}.t" "${_ADJ}"
_label "$(_rid 3)" true_catch "2027-04-05T00:00:00Z"
out="$(_status "2027-04-06T00:00:00Z")"
assert_contains "a label made after the deadline is ignored" "unresolved=1" "${out}"
assert_contains "the ignored label is reported" "made after 2027-03-31" "${out}"

# --- anything the reader cannot place BLOCKS the rule --------------------------
# Start from the corpus that reads MET and add a 30th record that cannot be
# placed. It may be a false block, so the rule must not read MET.
_extra() { # <jq-edit>
    _base
    _emit "${RA}" unexplained absent s30 "2026-10-10T10:00:00Z"
    tail -1 "${_CORP}" | jq -c "$1" > "${_CORP}.x"
    sed '$d' "${_CORP}" > "${_CORP}.t"; cat "${_CORP}.x" >> "${_CORP}.t"; mv "${_CORP}.t" "${_CORP}"; rm -f "${_CORP}.x"
}
while IFS='|' read -r _what _edit _needle; do
    [ -n "${_what}" ] || continue
    _extra "${_edit}"
    out="$(_status)"
    assert_contains     "uncountable (${_what}): the 29 valid episodes still read met" "[MET] 3." "${out}"
    assert_contains     "uncountable (${_what}): reported" "${_needle}" "${out}"
    assert_not_contains "uncountable (${_what}): never MET" "DECISION RULE MET" "${out}"
done <<EOF
empty ts|.ts = ""|unparseable ts : 1
pre-1970 ts|.ts = "1969-12-31T23:59:59Z"|unparseable ts : 1
no record_id|.record_id = ""|no usable record_id : 1
comma in record_id|.record_id = "aa,bb"|no usable record_id : 1
string predicate_version|.predicate_version = "2"|malformed predicate_version : 1
absent predicate_version|del(.predicate_version)|malformed predicate_version : 1
fractional predicate_version|.predicate_version = 2.5|malformed predicate_version : 1
unknown classification|.classification = "looks-fine"|unknown classification : 1
EOF

# nan parses as a JSON number in jq; written raw because jq prints it as null.
_base
_emit "${RA}" unexplained absent s30 "2026-10-10T10:00:00Z"
_l="$(tail -1 "${_CORP}")"; sed '$d' "${_CORP}" > "${_CORP}.t"
printf '%s\n' "${_l}" | sed 's/"predicate_version":2,/"predicate_version":nan,/' >> "${_CORP}.t"
if grep -q '"predicate_version":nan' "${_CORP}.t"; then _record_pass "nan fixture written"
else _record_fail "nan fixture written" "the substitution matched nothing — the cell below would be vacuous"; fi
mv "${_CORP}.t" "${_CORP}"
assert_not_contains "uncountable (nan predicate_version): never MET" "DECISION RULE MET" "$(_status)"

# A truncated line in the MIDDLE must not cut the corpus behind it.
_base
{ sed -n '1,10p' "${_CORP}"; printf '{"truncated": \n'; sed -n '11,29p' "${_CORP}"; } > "${_CORP}.t"; mv "${_CORP}.t" "${_CORP}"
out="$(_status)"
assert_contains     "malformed mid-corpus line: all 29 episodes still counted" "n=29" "${out}"
assert_contains     "malformed line is reported" "1 unparseable" "${out}"
assert_not_contains "malformed line: never MET" "DECISION RULE MET" "${out}"

# A duplicated record_id.
_base
{ sed -n '1p' "${_CORP}"; cat "${_CORP}"; } > "${_CORP}.t"; mv "${_CORP}.t" "${_CORP}"
out="$(_status)"
assert_contains     "duplicate record_id: reported" "DUPLICATE record_id : 1" "${out}"
assert_not_contains "duplicate record_id: never MET" "DECISION RULE MET" "${out}"

# A corrupt SIDECAR line could be hiding a false_block label.
_base; printf '{"record_id": \n' >> "${_ADJ}"
out="$(_status)"
assert_contains     "corrupt sidecar line: reported" "unparseable label line(s) : 1" "${out}"
assert_not_contains "corrupt sidecar line: never MET" "DECISION RULE MET" "${out}"

# A WHOLE-NUMBER other version is a legitimate older band: reported, not a
# blocker. Pinned, or the version bump in this very change would block for ever.
_base
tail -1 "${_CORP}" | jq -c '.predicate_version = 1 | .record_id = "0123456789abcdef" | .session_token = "old"' >> "${_CORP}"
out="$(_status)"
assert_contains "other-version record: reported" "other-predicate : 1" "${out}"
assert_contains "other-version record: not counted" "n=29" "${out}"
assert_contains "other-version record: does not block" "DECISION RULE MET" "${out}"
_rd 2026-10-20T00:00:00Z --adjudicate 0123456789abcdef --verdict true_catch >/dev/null 2>&1
assert_equals   "a record of another version cannot be labelled" "1" "$?"

# --- argument validation --------------------------------------------------------
_base
_rd 2026-10-20T00:00:00Z --adjudicate "$(_rid 1)" --verdict maybe >/dev/null 2>&1
assert_equals "an unknown verdict is refused" "1" "$?"
_rd 2026-10-20T00:00:00Z --adjudicate nosuchrecord --verdict true_catch >/dev/null 2>&1
assert_equals "an unknown record id is refused" "1" "$?"
_rd 2026-10-20T00:00:00Z --frobnicate >/dev/null 2>&1
assert_equals "an unknown argument is refused" "1" "$?"

# --- unreadable inputs are errors, never empty ----------------------------------
if [ "$(id -u)" != "0" ]; then
    _base; chmod 000 "${_CORP}"
    out="$(_status)"; chmod 600 "${_CORP}"
    assert_contains     "unreadable corpus is an ERROR" "NOT READABLE" "${out}"
    assert_not_contains "unreadable corpus is not reported as empty" "n=0" "${out}"
    _base; chmod 000 "${_ADJ}"
    out="$(_status)"; chmod 600 "${_ADJ}"
    assert_contains     "unreadable sidecar is an ERROR" "NOT READABLE" "${out}"
    assert_not_contains "unreadable sidecar: never MET" "DECISION RULE MET" "${out}"
else
    _record_pass "unreadable-input cells skipped (running as root; chmod 000 does not bind)"
fi

# --- the reader's version comes from the PRODUCER, proven by moving it ----------
RD="${TMP}/reader-tree"; mkdir -p "${RD}/hooks/lib" "${RD}/scripts"
cp "${PROJECT_ROOT}/hooks/lib/shadow-corpus.sh" "${RD}/hooks/lib/"
cp "${READER}" "${RD}/scripts/"
sed 's/^VERIFY_SHADOW_PREDICATE_VERSION=.*/VERIFY_SHADOW_PREDICATE_VERSION=7/' "${SHADOW_LIB}" > "${RD}/hooks/lib/verify-shadow.sh"
if cmp -s "${SHADOW_LIB}" "${RD}/hooks/lib/verify-shadow.sh"; then
    _record_fail "producer version moved in the copy" "sed changed nothing — the cell below would be vacuous"
else
    _record_pass "producer version moved in the copy"
fi
_reset
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
jq -c '.predicate_version = 7' "${_CORP}" > "${_CORP}.t" && mv "${_CORP}.t" "${_CORP}"
out="$(VERIFY_SHADOW_LOG="${_CORP}" VERIFY_ADJUDICATION_LOG="${_ADJ}" VERIFY_SHADOW_NOW="2026-10-20T00:00:00Z" /bin/bash "${RD}/scripts/verify-shadow-adjudicate.sh" --status 2>&1)"
assert_contains "reader follows a MOVED producer version" "n=1" "${out}"
assert_contains "the unmoved reader excludes that record" "n=0" "$(_status)"

# --- the shared corpus lib is required, never re-derived -------------------------
rm -f "${RD}/hooks/lib/shadow-corpus.sh"
VERIFY_SHADOW_LOG="${_CORP}" /bin/bash "${RD}/scripts/verify-shadow-adjudicate.sh" --status >/dev/null 2>&1
assert_equals "reader refuses to run without shadow-corpus.sh" "2" "$?"
assert_contains "reader groups episodes via the shared lib" "shadow_group_episodes" "$(cat "${READER}")"

# --- registered constants: reader vs design.md vs literals here ------------------
_matched=0
while IFS='|' read -r _const _val _needle; do
    [ -n "${_const}" ] || continue
    if grep -q "^${_const}=${_val}\$" "${READER}"; then
        _record_pass "reader constant ${_const}=${_val}"
    else
        _record_fail "reader constant ${_const}=${_val}" "not found verbatim in the reader"
    fi
    if grep -qF -- "${_needle}" "${DESIGN}"; then
        _record_pass "design.md states: ${_needle}"; _matched=$(( _matched + 1 ))
    else
        _record_fail "design.md states: ${_needle}" "the registration no longer says this"
    fi
done <<EOF
FLOOR_EPISODES|29|**n >= 29** would-block episodes
FLOOR_REPOS|2|**>= 2 distinct repositories**
BACKSTOP_MIN|3|fewer than **3** would-block episodes by **2026-12-31**
BACKSTOP_DATE|2026-12-31|fewer than **3** would-block episodes by **2026-12-31**
FINAL_DATE|2027-03-31|final deadline of **2027-03-31**
EPISODE_WINDOW_SEC|1800|within 30 minutes
ALPHA|0.05|one-sided 95%
DENY_P|0.10|below 10%
EOF
if [ "${_matched}" -ge 8 ]; then _record_pass "constant cross-check matched ${_matched} design clauses (floor 8)"
else _record_fail "constant cross-check matched ${_matched} design clauses" "floor is 8 — a reworded doc made the greps match nothing"; fi

print_summary
