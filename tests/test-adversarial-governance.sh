#!/usr/bin/env bash
# test-adversarial-governance.sh — Governance constraint regression assertions
# Validates that required safety invariants are present in key skills and compositions.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-adversarial-governance.sh ==="

# --- REVIEW composition: adversarial checklist ---
REGISTRY="${PROJECT_ROOT}/config/default-triggers.json"
REGISTRY_CONTENT="$(cat "${REGISTRY}")"
FALLBACK="${PROJECT_ROOT}/config/fallback-registry.json"
FALLBACK_CONTENT="$(cat "${FALLBACK}")"

assert_contains "adversarial checklist in REVIEW hints (default)" "ADVERSARIAL REVIEW" "${REGISTRY_CONTENT}"
assert_contains "adversarial checklist in REVIEW hints (fallback)" "ADVERSARIAL REVIEW" "${FALLBACK_CONTENT}"
assert_contains "HITL check in adversarial checklist" "safety gate, HITL requirement" "${REGISTRY_CONTENT}"
assert_contains "bypass patterns in adversarial checklist" "dangerouslyDisableSandbox" "${REGISTRY_CONTENT}"

# --- Autonomy<->control coherence (DESIGN) ---
assert_contains "autonomy check in DESIGN hints (default)" "AUTONOMY CHECK" "${REGISTRY_CONTENT}"
assert_contains "autonomy check in DESIGN hints (fallback)" "AUTONOMY CHECK" "${FALLBACK_CONTENT}"
assert_contains "autonomy principle stated (default)" "autonomy without proportional control is a liability" "${REGISTRY_CONTENT}"
assert_contains "autonomy principle stated (fallback)" "autonomy without proportional control is a liability" "${FALLBACK_CONTENT}"
assert_contains "autonomy hint is advisory not a gate (default)" "this is guidance, not a gate" "${REGISTRY_CONTENT}"
assert_contains "autonomy hint is advisory not a gate (fallback)" "this is guidance, not a gate" "${FALLBACK_CONTENT}"

# --- agent-safety-review: design-time governance ---
SAFETY_SKILL="${PROJECT_ROOT}/skills/agent-safety-review/SKILL.md"
SAFETY_CONTENT="$(cat "${SAFETY_SKILL}")"

assert_contains "agent-safety-review: lethal trifecta" "lethal trifecta" "${SAFETY_CONTENT}"
assert_contains "agent-safety-review: blast-radius" "blast-radius" "${SAFETY_CONTENT}"
# Frontmatter description follows the catalog "Use when…" trigger convention
# (catalog surface only — routing is regex-based; cf. the 8-skill alignment in #62).
assert_contains "agent-safety-review: description uses 'Use when' trigger form" "Use when" "$(sed -n '3p' "${SAFETY_SKILL}")"

# --- agent-team-review: adversarial reviewer ---
TEAM_SKILL="${PROJECT_ROOT}/skills/agent-team-review/SKILL.md"
TEAM_CONTENT="$(cat "${TEAM_SKILL}")"

assert_contains "agent-team-review: adversarial-reviewer template" "adversarial-reviewer" "${TEAM_CONTENT}"
assert_contains "agent-team-review: governance lens" "Governance" "${TEAM_CONTENT}"
assert_contains "agent-team-review: HITL in adversarial focus" "HITL" "${TEAM_CONTENT}"
assert_contains "agent-team-review: safety gate in adversarial focus" "safety gate" "${TEAM_CONTENT}"

# --- agent-team-review: doubt discipline (change: adopt-doubt-discipline) ---
assert_contains "agent-team-review: claim-withheld dispatch" "artifact and the contract" "${TEAM_CONTENT}"
assert_contains "agent-team-review: implementer self-summary excluded" "self-summary" "${TEAM_CONTENT}"
assert_contains "agent-team-review: doubt-theater red flag" "doubt theater" "${TEAM_CONTENT}"
assert_contains "agent-team-review: doubt-theater meaning" "validating, not reviewing" "${TEAM_CONTENT}"

# --- agent-team-review: proportionality / root-cause question (narrowed claude-mem merge-rubric
# adoption; the rubric itself is NOT imported — as written it would condemn this repo's
# deliberate fail-open hooks, bridges and canaries).
# Scoped to the quality-reviewer block on purpose: the same words under another lens would be a
# different contract, and a whole-file needle cannot tell the two apart.
# The range STOPS AT THE NEXT reviewer header generically, not at a hardcoded one: `spec-reviewer`
# sits between quality- and adversarial-reviewer, so terminating on "adversarial-reviewer" silently
# swallowed the spec block too and a bullet misplaced there would have passed. Anchored with `^\s*name:`
# so the sibling `team_name:` line cannot terminate the range early.
QUALITY_BLOCK="$(awk '/^[[:space:]]*name: "quality-reviewer"/{f=1;next} f && /^[[:space:]]*name: "/{exit} f' "${TEAM_SKILL}")"
if [ -z "${QUALITY_BLOCK}" ]; then
    _record_fail "agent-team-review: quality-reviewer block extracted" "non-empty block" "empty — anchors moved, assertions below prove nothing"
fi
assert_contains "agent-team-review: quality lens asks proportionality" "proportional to the defect" "${QUALITY_BLOCK}"
assert_contains "agent-team-review: quality lens asks root cause vs route-around" "route around one that stays unfixed" "${QUALITY_BLOCK}"
assert_contains "agent-team-review: compensating layer legitimate when root cause also fixed" "residual gap it closes is stated" "${QUALITY_BLOCK}"

# --- agent-team-review: finding evidence + confidence + severity floor (v1 false-positive discipline) ---
# Cheapest-alternative controls that any future adversarial-refute gate must beat.
assert_contains "agent-team-review: confidence field in FINDING" "Confidence: high | medium | low" "${TEAM_CONTENT}"
assert_contains "agent-team-review: evidence field in FINDING" "Evidence: observable failure path" "${TEAM_CONTENT}"
assert_contains "agent-team-review: blocking requires observable failure path" "observable failure path" "${TEAM_CONTENT}"
assert_contains "agent-team-review: severity floor" "Severity floor" "${TEAM_CONTENT}"
assert_contains "agent-team-review: security/governance exempt from drop AND demote" "Never drop or demote \`security\` or \`governance\` findings" "${TEAM_CONTENT}"
assert_contains "agent-team-review: structural blocking for security/governance" "structural grounds" "${TEAM_CONTENT}"
assert_contains "agent-team-review: confidence is advisory only" "Confidence is advisory only" "${TEAM_CONTENT}"
assert_contains "agent-team-review: permissions in description trigger" "auth/secrets/permissions/hooks/CI" "${TEAM_CONTENT}"
assert_contains "agent-team-review: dropped suggestions stay visible" "below severity floor" "${TEAM_CONTENT}"
assert_contains "agent-team-review: no silent discard of floored findings" "Never silently discard" "${TEAM_CONTENT}"
assert_contains "agent-team-review: reviewers emit confidence/evidence" "including the Confidence and Evidence fields" "${TEAM_CONTENT}"
assert_contains "agent-team-review: cross-model offer" "Codex" "${TEAM_CONTENT}"
assert_contains "agent-team-review: cross-model no silent skip" "silently skipping is not" "${TEAM_CONTENT}"
assert_contains "agent-team-review: cross-model sandboxed" "injected instructions" "${TEAM_CONTENT}"
assert_contains "agent-team-review: sensitive-path override" "regardless of file count" "${TEAM_CONTENT}"

# --- Eval/safety gate deltas (change: eval-safety-gate-deltas) ---
# Safety is the first-class, non-negotiable gate: classify probabilistic-vs-
# deterministic at DESIGN (model-asks, no AI-feature auto-trigger); safety eval
# cases red before code; safety-relevant runtime paths exercised; eval scenarios
# append-only.

# DESIGN-phase EVAL STRATEGY hint: classify probabilistic-vs-deterministic, ask if unclear.
assert_contains "EVAL STRATEGY hint in DESIGN hints (default)" "EVAL STRATEGY" "${REGISTRY_CONTENT}"
assert_contains "EVAL STRATEGY hint in DESIGN hints (fallback)" "EVAL STRATEGY" "${FALLBACK_CONTENT}"
assert_contains "EVAL STRATEGY: classify (model-asks, not regex)" "ask the user if" "${REGISTRY_CONTENT}"
assert_contains "EVAL STRATEGY: adversarial/safety subset" "adversarial/safety subsets" "${REGISTRY_CONTENT}"
assert_contains "EVAL STRATEGY: red before implementation" "failing (red) before implementation" "${REGISTRY_CONTENT}"

# runtime-validation: safety-relevant paths must be exercised + eval scenarios append-only.
RTV_SKILL="${PROJECT_ROOT}/skills/runtime-validation/SKILL.md"
RTV_CONTENT="$(cat "${RTV_SKILL}")"
assert_contains "runtime-validation: safety-relevant paths section" "Safety-Relevant Paths" "${RTV_CONTENT}"
assert_contains "runtime-validation: safety paths must be exercised" "MUST be exercised" "${RTV_CONTENT}"
assert_contains "runtime-validation: eval scenarios append-only" "append-only" "${RTV_CONTENT}"
# CLI scenario execution must not `eval` eval-pack-sourced command strings (shell-injection vector).
assert_not_contains "runtime-validation: no eval of eval-pack command (injection)" 'eval "${cmd}"' "${RTV_CONTENT}"
assert_contains "runtime-validation: eval-pack trust-boundary note" "TRUSTED committed fixtures" "${RTV_CONTENT}"

# frontend-quality-rules: advisory routing to EXTERNAL Vercel skills must stay conditional,
# must not hardcode an unknowable Skill() invocation token for a namespace we don't own,
# and must name our own fallback so a stale/absent reference degrades to silence.
FQR_HINT="$(jq -r '.methodology_hints[] | select(.name=="frontend-quality-rules") | .hint' "${REGISTRY}" 2>/dev/null)"
FQR_PHASES="$(jq -r '.methodology_hints[] | select(.name=="frontend-quality-rules") | .phases[]' "${REGISTRY}" 2>/dev/null)"
assert_contains "frontend-quality: hint present" "FRONTEND QUALITY" "${FQR_HINT}"
assert_contains "frontend-quality: names web-interface-guidelines" "web-interface-guidelines" "${FQR_HINT}"
assert_contains "frontend-quality: names react-best-practices" "react-best-practices" "${FQR_HINT}"
assert_contains "frontend-quality: names our fallback (runtime-validation)" "runtime-validation" "${FQR_HINT}"
assert_contains "frontend-quality: conditional wording (is installed)" "is installed" "${FQR_HINT}"
assert_not_contains "frontend-quality: no hardcoded Skill() for web-interface-guidelines" "Skill(web-interface-guidelines" "${FQR_HINT}"
assert_not_contains "frontend-quality: no hardcoded Skill() for react-best-practices" "Skill(react-best-practices" "${FQR_HINT}"
assert_contains "frontend-quality: fires in IMPLEMENT" "IMPLEMENT" "${FQR_PHASES}"
assert_contains "frontend-quality: fires in REVIEW" "REVIEW" "${FQR_PHASES}"
# fallback registry must carry the same hint (drift guard)
assert_contains "frontend-quality: mirrored to fallback registry" "frontend-quality-rules" "${FALLBACK_CONTENT}"

# agent-safety-review: safety eval cases red before code (TDD-for-evals).
assert_contains "agent-safety-review: safety eval red before code" "before the behavior is implemented" "${SAFETY_CONTENT}"
assert_contains "agent-safety-review: compose with TDD" "test-driven-development" "${SAFETY_CONTENT}"

# agent-safety-review: Step 2b autonomy-control coherence backstop (additive).
assert_contains "agent-safety-review: Step 2b autonomy coherence" "Step 2b" "${SAFETY_CONTENT}"
assert_contains "agent-safety-review: autonomy ladder rungs" "execute-reversible" "${SAFETY_CONTENT}"
assert_contains "agent-safety-review: additive-only note (does not change trifecta)" "does not change the trifecta" "${SAFETY_CONTENT}"
assert_contains "agent-safety-review: output autonomy row" "Autonomy:" "${SAFETY_CONTENT}"

# ---------------------------------------------------------------------------
# Do-not-flag list + authorship guard (adopt-review-independence)
#
# GOVERNANCE INVARIANT: the do-not-flag list is a REVIEWER SCOPE rule with
# exactly TWO ownership categories. It must never become a synthesis-side
# provenance filter, and must never grow a category that demotes a finding by
# its provenance — either shape would suppress the structural security and
# governance findings that the severity floor and the Evidence exception exist
# to protect.
#
# These assertions are SEMANTIC, not substring greps, because a grep cannot
# tell a refusal from an embrace: an earlier draft asserted the presence of the
# word "speculative" and was satisfied by unrelated pre-existing text in the
# quality-reviewer lens, so it passed against a doc that ADDED a `speculative`
# row. Adding a third row and adding a §4 filter step were both green.
# ---------------------------------------------------------------------------
ATR="${PROJECT_ROOT}/skills/agent-team-review/SKILL.md"
assert_file_exists "agent-team-review SKILL.md exists" "${ATR}"
atr="$(cat "${ATR}" 2>/dev/null)"

assert_contains "do-not-flag list present"                 "Do not flag"                        "${atr}"
assert_contains "do-not-flag is reviewer scope, not a lead filter" \
    "NOT a filter the lead applies afterwards"                                                  "${atr}"

# (a) EXACTLY TWO do-not-raise rows. A third row is the mutation that a
#     presence-grep cannot see. Count rows in the table between the heading and
#     the paragraph that closes it.
dnf_rows="$(awk '/^\*\*Do not flag/{f=1} f&&/^\| `[a-z-]+` /{n++} f&&/^The list stops at two/{exit} END{print n+0}' "${ATR}")"
assert_equals "do-not-flag table has exactly 2 rows" "2" "${dnf_rows}"
assert_contains "do-not-flag row: pre-existing"            '| `pre-existing`'                   "${atr}"
assert_contains "do-not-flag row: tool-owned"              '| `tool-owned`'                     "${atr}"

# (b) The forbidden shapes, asserted as ABSENT rather than inferred from prose.
assert_not_contains "no speculative do-not-raise row"      '| `speculative`'                    "${atr}"

# (a2) #245 — the SAME invariant on the copy that actually reaches a reviewer.
#      §3 is prose the lead reads; a spawned reviewer sees only its own prompt,
#      so the two-category ceiling has to hold in the delivered text as well, or
#      a third category can be added where the lead-side assertion cannot see it.
#      Counted per lens, not whole-file: a whole-file count cannot tell "two
#      categories in each of four prompts" from "eight in one".
while IFS= read -r _lens; do
    [ -n "${_lens}" ] || continue
    _scope="$(awk -v lens="${_lens}" '
        $0 ~ "^[[:space:]]*name: \"" lens "\"" { f=1; next }
        f && /^[[:space:]]*name: "/ { exit }
        f && /^## / { exit }
        f && /^[[:space:]]*## Scope/ { s=1; next }
        s && /^[[:space:]]*## / { exit }
        s
    ' "${ATR}")"
    _cats="$(printf '%s\n' "${_scope}" | grep -c 'Do not raise `[a-z-]*`')"
    assert_equals "${_lens}: reviewer scope block stops at two categories" "2" "${_cats}"
    assert_not_contains "${_lens}: no speculative category in the delivered copy" \
        'Do not raise `speculative`' "${_scope}"
done <<'LENS_EOF'
security-reviewer
quality-reviewer
spec-reviewer
adversarial-reviewer
LENS_EOF

# (a3) The lead-side table must SAY where the reviewer copy lives, so the next
#      editor changes both. Without this the two copies drift silently, which is
#      the #166 shape this pairing note exists to prevent.
assert_contains "do-not-flag table names its paired reviewer copy" \
    "the reviewer's copy ships in the spawn" "${atr}"
assert_not_contains "no synthesis-side provenance filter"  "Provenance filter"                  "${atr}"
assert_not_contains "no category-based drop at synthesis"  "drop any finding whose category"    "${atr}"

# (c) §4 synthesis must carry exactly ONE numbered drop/demote step (the
#     severity floor). A second one is the lead-filter mutation.
floor_steps="$(awk '/^### 4\. Lead Synthesis/{f=1} f&&/^[0-9]+\. \*\*Severity floor/{n++} f&&/^### 4a\./{exit} END{print n+0}' "${ATR}")"
assert_equals "§4 has exactly one severity-floor step" "1" "${floor_steps}"
assert_contains "severity floor still protects security/governance" \
    'Never drop or demote `security` or `governance` findings'                                  "${atr}"

# (d) The authorship guard withdraws the CLAIM. Pin the operative clause, not a
#     prefix — "keep every" survives a rewrite to "keep every finding, but
#     demote each one severity level", which is the shape the skill forbids.
assert_contains "authorship guard present"                 "Authorship guard"                   "${atr}"
assert_contains "authorship guard: self-review is convention-checking" \
    "convention-checking"                                                                       "${atr}"
assert_contains "authorship guard keeps earned severity"   "at the severity its evidence earns" "${atr}"
assert_not_contains "authorship guard does not demote per level" "demote each"                  "${atr}"
assert_not_contains "authorship guard does not demote by level"  "one severity level"           "${atr}"
assert_not_contains "authorship guard does not downgrade findings" "downgrade the finding"      "${atr}"

# (e) #245 — the guard's "nothing else will" is now false: the verdict artifact
#     carries the declaration. Pin the prose to the MECHANISM in both
#     directions, so neither can be removed while the other keeps claiming it.
#     The second assertion reads the real producer rather than a copy of the
#     flag name, which is the only way a renamed flag fails here instead of
#     shipping a skill that instructs an unknown argument.
assert_contains "authorship guard names the recording flag" "--self-authored" "${atr}"
_rrv="${PROJECT_ROOT}/scripts/record-review-verdict.sh"
if grep -q -- '--self-authored)' "${_rrv}" 2>/dev/null; then
    _record_pass "record-review-verdict.sh accepts the flag the skill instructs"
else
    _record_fail "record-review-verdict.sh accepts the flag the skill instructs" \
        "no --self-authored) arm in ${_rrv} — the skill instructs an argument the script rejects"
fi
# Provenance, never a gate (#197). The guard must not branch on the field.
if grep -q 'independence' "${PROJECT_ROOT}/hooks/openspec-guard.sh" 2>/dev/null; then
    _record_fail "independence is not read by the push gate" \
        "openspec-guard.sh references 'independence' — #197 forbids provenance from gating"
else
    _record_pass "independence is not read by the push gate"
fi

# Summary
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="

if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi
