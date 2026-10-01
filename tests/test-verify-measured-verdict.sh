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
assert_equals "record: schema_version"    "1" "$(_lastf .schema_version)"
assert_equals "record: predicate_version" "1" "$(_lastf .predicate_version)"
assert_equals "record: repo is the toplevel" "${RA}" "$(_lastf .repo)"
assert_equals "record: repo_id is the ORIGIN, not the path" "https://example.invalid/org/a.git" "$(_lastf .repo_id)"
assert_equals "record: branch"   "feat" "$(_lastf .branch)"
assert_equals "record: head_sha" "$(_head "${RA}")" "$(_lastf .head_sha)"
assert_equals "record: session_token" "${_TOK}" "$(_lastf .session_token)"
assert_equals "record: transcript pointer" "${_TPATH}" "$(_lastf .transcript_path)"
assert_equals "record: material_source is a boolean" "boolean" "$(_lastf '.material_source|type')"
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
assert_equals       "record: repo_id survives the strip" "https://example.invalid/org/b.git" "$(_lastf .repo_id)"
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
# 6. The reader. Corpora come from the REAL recorder; only ts is patched.
# ---------------------------------------------------------------------------
_CORP="${TMP}/corpus.jsonl"
_emit() { # <repo> <class> <reason> <token> <ts>
    VERIFY_SHADOW_LOG="${_CORP}" verify_shadow_record "$4" "$1" "$2" "$3" push HEAD "" false ""
    local _l; _l="$(tail -1 "${_CORP}")"
    sed '$d' "${_CORP}" > "${_CORP}.t"
    printf '%s\n' "${_l}" | jq -c --arg ts "$5" '.ts = $ts' >> "${_CORP}.t"
    mv "${_CORP}.t" "${_CORP}"
}
_status() { # [now-iso]
    VERIFY_SHADOW_LOG="${_CORP}" VERIFY_SHADOW_NOW="${1:-2026-10-20T00:00:00Z}" \
        /bin/bash "${READER}" --status 2>&1
}

# --- no corpus, and an unreadable one, are different statements -------------
rm -f "${_CORP}"
out="$(_status)"
assert_contains "no corpus is reported as no corpus" "no corpus yet" "${out}"
assert_contains "no corpus => decision rule not met" "DECISION RULE NOT MET" "${out}"

# --- round trip: a record written by the REAL GUARD is counted --------------
rm -f "${_VLOG}" "${_ART}"; _seed_status "${_BOTH}"
_guard "${PROJECT_ROOT}" "${RA}" "git push origin HEAD" >/dev/null
out="$(VERIFY_SHADOW_LOG="${_VLOG}" /bin/bash "${READER}" --status 2>&1)"
assert_contains "round trip: guard-written record is one episode" "n=1" "${out}"
assert_contains "round trip: classified unexplained" "unexplained=1" "${out}"

# --- episode grouping: anchored 30 minutes, same (repo, branch, token) ------
rm -f "${_CORP}"
_emit "${RA}" unexplained absent tok1 "2026-10-05T10:00:00Z"
_emit "${RA}" unexplained absent tok1 "2026-10-05T10:20:00Z"   # +20m: same episode
_emit "${RA}" unexplained absent tok1 "2026-10-05T10:40:00Z"   # +40m from ANCHOR: new episode
out="$(_status)"
assert_contains "three records, anchored window => two episodes" "n=2" "${out}"
assert_contains "record count is reported separately from n" "3 line(s)" "${out}"

# --- two worktrees of ONE repository are one repo ---------------------------
rm -f "${_CORP}"
_emit "${RA}"    explained_ladder hand-authored tokA "2026-10-05T10:00:00Z"
_emit "${RA_WT}" explained_ladder hand-authored tokB "2026-10-06T10:00:00Z"
out="$(_status)"
assert_contains "two worktrees, one origin => 1 distinct repo" "repos=1" "${out}"

# --- the decision rule, clause by clause ------------------------------------
_five() { # <repo-for-5th> <class-for-5th> <reason>
    rm -f "${_CORP}"
    _emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
    _emit "${RA}" explained_ladder hand-authored t2 "2026-10-06T10:00:00Z"
    _emit "${RA}" cannot_check unparseable       t3 "2026-10-07T10:00:00Z"
    _emit "${RA}" explained_ladder hand-authored t4 "2026-10-08T10:00:00Z"
    _emit "$1" "$2" "$3"                         t5 "2026-10-09T10:00:00Z"
}
_five "${RB}" explained_ladder hand-authored
out="$(_status)"
assert_contains "all four clauses met: clause 1" "[MET] 1." "${out}"
assert_contains "all four clauses met: clause 2" "[MET] 2." "${out}"
assert_contains "all four clauses met: clause 3" "[MET] 3." "${out}"
assert_contains "all four clauses met: clause 4" "[MET] 4." "${out}"
assert_contains "all four clauses met => rule met" "DECISION RULE MET" "${out}"
assert_contains "the reader authorises nothing by itself" "separate change" "${out}"

_five "${RA}" explained_ladder hand-authored
out="$(_status)"
assert_contains "one repository => clause 4 unmet" "[UNMET] 4." "${out}"
assert_contains "one repository => rule not met" "DECISION RULE NOT MET" "${out}"

_five "${RB}" unexplained absent
out="$(_status)"
assert_contains "one unexplained => clause 2 unmet" "[UNMET] 2." "${out}"
assert_contains "one unexplained => rule not met" "DECISION RULE NOT MET" "${out}"

# Positive-control clause: five episodes, zero unexplained, NONE explained.
rm -f "${_CORP}"
_emit "${RA}" cannot_check unparseable t1 "2026-10-05T10:00:00Z"
_emit "${RA}" cannot_check unparseable t2 "2026-10-06T10:00:00Z"
_emit "${RA}" cannot_check unparseable t3 "2026-10-07T10:00:00Z"
_emit "${RB}" cannot_check unparseable t4 "2026-10-08T10:00:00Z"
_emit "${RB}" cannot_check unparseable t5 "2026-10-09T10:00:00Z"
out="$(_status)"
assert_contains "no explained_ladder => clause 1 still met" "[MET] 1." "${out}"
assert_contains "no explained_ladder => clause 3 UNMET" "[UNMET] 3." "${out}"
assert_contains "no explained_ladder => rule not met (positive-control failure)" "DECISION RULE NOT MET" "${out}"

# Four episodes is below the floor.
rm -f "${_CORP}"
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
_emit "${RA}" explained_ladder hand-authored t2 "2026-10-06T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t3 "2026-10-07T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t4 "2026-10-08T10:00:00Z"
out="$(_status)"
assert_contains "n=4 => clause 1 unmet" "[UNMET] 1." "${out}"

# Within one episode, unexplained WINS regardless of arrival order.
rm -f "${_CORP}"
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
_emit "${RA}" unexplained absent             t1 "2026-10-05T10:05:00Z"
out="$(_status)"
assert_contains "mixed episode (explained first) => unexplained" "unexplained=1" "${out}"
rm -f "${_CORP}"
_emit "${RA}" unexplained absent             t1 "2026-10-05T10:00:00Z"
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:05:00Z"
out="$(_status)"
assert_contains "mixed episode (unexplained first) => unexplained" "unexplained=1" "${out}"
assert_contains "mixed episode is ONE episode" "n=1" "${out}"

# --- starvation backstop ----------------------------------------------------
rm -f "${_CORP}"
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t2 "2026-10-06T10:00:00Z"
out="$(_status "2026-11-01T00:00:00Z")"
assert_contains "before the deadline the window is open" "backstop : OPEN" "${out}"
out="$(_status "2027-01-05T00:00:00Z")"
assert_contains "n<3 at the deadline => closed as a null result" "NULL RESULT" "${out}"
# Episodes arriving AFTER the deadline cannot reopen a closed window.
_emit "${RA}" explained_ladder hand-authored t3 "2027-01-02T10:00:00Z"
_emit "${RA}" explained_ladder hand-authored t4 "2027-01-03T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t5 "2027-01-04T10:00:00Z"
out="$(_status "2027-01-05T00:00:00Z")"
assert_contains "late episodes: all four clauses read met" "[MET] 1." "${out}"
assert_contains "late episodes do not reopen the window" "NULL RESULT" "${out}"
assert_not_contains "a closed window never reports the rule met" "DECISION RULE MET" "${out}"
# Three by the deadline clears the backstop.
rm -f "${_CORP}"
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t2 "2026-10-06T10:00:00Z"
_emit "${RB}" explained_ladder hand-authored t3 "2026-12-31T23:00:00Z"
out="$(_status "2027-01-05T00:00:00Z")"
assert_contains "n>=3 by the deadline => backstop cleared" "backstop : CLEARED" "${out}"

# --- corrupt, foreign and unusable records are REPORTED, never silent -------
_five "${RB}" explained_ladder hand-authored
_base="$(_status)"
# A malformed line in the MIDDLE must not truncate the corpus behind it.
{ sed -n '1,2p' "${_CORP}"; printf '{"truncated": \n'; sed -n '3,5p' "${_CORP}"; } > "${_CORP}.t"
mv "${_CORP}.t" "${_CORP}"
out="$(_status)"
assert_contains "malformed mid-corpus line: all five episodes still counted" "n=5" "${out}"
assert_contains "malformed line is reported" "1 unparseable" "${out}"

_five "${RB}" explained_ladder hand-authored
tail -1 "${_CORP}" | jq -c '.predicate_version = 99' > "${_CORP}.x"
sed '$d' "${_CORP}" > "${_CORP}.t"; cat "${_CORP}.x" >> "${_CORP}.t"; mv "${_CORP}.t" "${_CORP}"; rm -f "${_CORP}.x"
out="$(_status)"
assert_contains "other-predicate record is excluded from n" "n=4" "${out}"
assert_contains "other-predicate record is REPORTED" "other-predicate : 1" "${out}"

_five "${RB}" explained_ladder hand-authored
tail -1 "${_CORP}" | jq -c '.ts = ""' > "${_CORP}.x"
sed '$d' "${_CORP}" > "${_CORP}.t"; cat "${_CORP}.x" >> "${_CORP}.t"; mv "${_CORP}.t" "${_CORP}"; rm -f "${_CORP}.x"
out="$(_status)"
assert_contains "unusable-ts record is excluded from n" "n=4" "${out}"
assert_contains "unusable-ts record is REPORTED" "unparseable ts : 1" "${out}"

_five "${RB}" explained_ladder hand-authored
# APPENDED as a sixth record, not swapped in for the fifth: with only four valid
# episodes left the floor fails by itself and the cell passes with the
# unknown-classification check deleted (mutation-verified). Here all four
# clauses hold over the five valid episodes, so only that check can say NOT MET.
tail -1 "${_CORP}" | jq -c '.classification = "looks-fine" | .record_id = "feedfacefeedface" | .session_token = "t6"' >> "${_CORP}"
out="$(_status)"
assert_contains "unknown classification: the five valid episodes still count" "n=5" "${out}"
assert_contains "unknown classification: all four clauses read met" "[MET] 4." "${out}"
assert_contains "unknown classification is REPORTED" "unknown classification : 1" "${out}"
assert_contains "unknown classification never clears the rule" "DECISION RULE NOT MET" "${out}"

if [ "$(id -u)" != "0" ]; then
    _five "${RB}" explained_ladder hand-authored
    chmod 000 "${_CORP}"
    out="$(_status)"
    chmod 600 "${_CORP}"
    assert_contains     "unreadable corpus is an ERROR" "NOT READABLE" "${out}"
    assert_not_contains "unreadable corpus is not reported as empty" "n=0" "${out}"
else
    _record_pass "unreadable-corpus cells skipped (running as root; chmod 000 does not bind)"
fi

# --- the reader's version comes from the PRODUCER, proven by moving it ------
RD="${TMP}/reader-tree"; mkdir -p "${RD}/hooks/lib" "${RD}/scripts"
cp "${PROJECT_ROOT}/hooks/lib/shadow-corpus.sh" "${RD}/hooks/lib/"
cp "${READER}" "${RD}/scripts/"
sed 's/^VERIFY_SHADOW_PREDICATE_VERSION=.*/VERIFY_SHADOW_PREDICATE_VERSION=7/' "${SHADOW_LIB}" > "${RD}/hooks/lib/verify-shadow.sh"
if cmp -s "${SHADOW_LIB}" "${RD}/hooks/lib/verify-shadow.sh"; then
    _record_fail "producer version moved in the copy" "sed changed nothing — the cell below would be vacuous"
else
    _record_pass "producer version moved in the copy"
fi
rm -f "${_CORP}"
_emit "${RA}" explained_ladder hand-authored t1 "2026-10-05T10:00:00Z"
jq -c '.predicate_version = 7' "${_CORP}" > "${_CORP}.t" && mv "${_CORP}.t" "${_CORP}"
out="$(VERIFY_SHADOW_LOG="${_CORP}" VERIFY_SHADOW_NOW="2026-10-20T00:00:00Z" /bin/bash "${RD}/scripts/verify-shadow-adjudicate.sh" --status 2>&1)"
assert_contains "reader follows a MOVED producer version" "n=1" "${out}"
out="$(_status)"
assert_contains "the unmoved reader excludes that record" "n=0" "${out}"

# --- shared corpus lib is required, never re-derived ------------------------
rm -f "${RD}/hooks/lib/shadow-corpus.sh"
VERIFY_SHADOW_LOG="${_CORP}" /bin/bash "${RD}/scripts/verify-shadow-adjudicate.sh" --status >/dev/null 2>&1
assert_equals "reader refuses to run without shadow-corpus.sh" "2" "$?"
assert_contains "reader groups episodes via the shared lib" "shadow_group_episodes" "$(cat "${READER}")"

# --- pre-registered constants: reader vs design.md vs literals here ---------
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
        _record_fail "design.md states: ${_needle}" "the pre-registration no longer says this"
    fi
done <<EOF
FLOOR_EPISODES|5|**n >= 5** shadow episodes
FLOOR_REPOS|2|**>= 2 distinct repos**
BACKSTOP_MIN|3|**n < 3** by **2026-12-31**
BACKSTOP_DATE|2026-12-31|**n < 3** by **2026-12-31**
EPISODE_WINDOW_SEC|1800|within 30 minutes
EOF
if [ "${_matched}" -ge 5 ]; then _record_pass "constant cross-check matched ${_matched} design clauses (floor 5)"
else _record_fail "constant cross-check matched ${_matched} design clauses" "floor is 5 — a reworded doc made the greps match nothing"; fi

print_summary
