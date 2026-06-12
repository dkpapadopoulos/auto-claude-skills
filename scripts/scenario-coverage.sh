#!/bin/bash
# scenario-coverage.sh — advisory behavioral-pack coverage report.
#
# Surfaces the spec->eval gap: which skill-execution capabilities describe
# probabilistic model behavior in their acceptance scenarios but have NO
# behavioral eval pack (consumed by tests/run-behavioral-evals.sh) guarding it.
#
# Scope (deliberate, per openspec/changes/archive/*-spec-eval-loop-decision):
#   - It reports *linkage existence* (does a behavioral pack exist for this
#     capability), NOT scenario-level assertion coverage. Scenarios have no
#     stable IDs to link to pack cases, and faking a percentage would be the
#     over-precise gate the design debate rejected.
#   - A capability is in scope only if a runnable skills/<cap>/SKILL.md exists
#     AND its spec has >= THRESHOLD probabilistic-verb THEN clauses. Pure
#     hook/registry/state capabilities (skill-routing, behavioral-evaluation,
#     etc.) are out of scope — they are covered deterministically by the bash
#     suite (test-routing.sh, test-openspec-state.sh, ...).
#
# Advisory + fail-open: exits 0 unless --strict AND a real uncovered gap exists.
# Intended for the opt-in BEHAVIORAL_EVALS=1 CI path, NOT the default suite.
#
# Bash 3.2 compatible. No associative arrays.

ROOT="."
STRICT=0
THRESHOLD=3

while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-.}"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        --threshold) THRESHOLD="${2:-3}"; shift 2 ;;
        *) shift ;;
    esac
done

# Probabilistic model-output verbs: a THEN clause using one of these describes
# generated/judged model behavior (only observable by running the SKILL.md),
# as opposed to a deterministic hook-output string or state value.
PROB='fall[s]?[ -]?back|recommend|explain|describe|summari|prioriti|identif|classif|attribut|surface|note[s]? that|warn|suggest|flag|ask|acknowledg|mention|refuse|fabricat|diagnos|propose|infer|extract|group|comput|assign|cite'

# Static-artifact negative filter: a clause that matches a probabilistic VERB but
# whose SUBJECT is a doc/banner/config artifact (not the model) is a deterministic
# content assertion — already covered by grep-based tests, not behavioral. These
# are subtracted from the probabilistic count to stop documentation/guidance
# capabilities (e.g. unified-context-stack) from being over-flagged.
NEG='banner|phase doc|tier doc|\bthe doc\b|\.md\b|appears? in|MUST (mention|contain|name|assert|NOT (mention|contain))|context-capability|flag MUST|MUST default|SHALL (provide|expose)'

SPECS_DIR="${ROOT}/openspec/specs"
if [ ! -d "${SPECS_DIR}" ]; then
    echo "scenario-coverage: no specs directory at ${SPECS_DIR} (nothing to report)"
    exit 0
fi

uncovered=0
haspack=0
total=0
uncovered_list=""

printf '%-30s %-9s %-6s %s\n' "CAPABILITY" "PROB-THEN" "CASES" "STATUS"
printf '%-30s %-9s %-6s %s\n' "------------------------------" "---------" "-----" "------"

for spec in "${SPECS_DIR}"/*/spec.md; do
    [ -f "${spec}" ] || continue
    cap="$(basename "$(dirname "${spec}")")"

    # In scope only if a runnable SKILL.md exists for this capability.
    [ -f "${ROOT}/skills/${cap}/SKILL.md" ] || continue

    # Count probabilistic-verb matches in OUTCOME lines only:
    #   - drop markdown headings (### Requirement: / #### Scenario:) — titles, not behavior
    #   - drop GIVEN/WHEN preconditions — they describe inputs, not asserted output
    #   - drop static-artifact (NEG) assertions — deterministic doc/banner/config content
    pcount="$(grep -iE "(${PROB})" "${spec}" 2>/dev/null \
        | grep -vE '^[[:space:]]*#' \
        | grep -ivE '^[[:space:]]*(-[[:space:]]*)?(\*\*)?(given|when)\b' \
        | grep -icvE "(${NEG})")"
    [ -n "${pcount}" ] || pcount=0
    [ "${pcount}" -ge "${THRESHOLD}" ] || continue

    total=$((total + 1))

    pack=""
    for cand in "tests/fixtures/${cap}/evals/behavioral.json" "tests/fixtures/${cap}/behavioral.json"; do
        if [ -f "${ROOT}/${cand}" ]; then
            pack="${ROOT}/${cand}"
            break
        fi
    done

    if [ -z "${pack}" ]; then
        cases=0
    else
        cases="$(jq 'length' "${pack}" 2>/dev/null)"
        [ -n "${cases}" ] || cases=0
    fi

    if [ "${cases}" -eq 0 ]; then
        status="UNCOVERED"
        uncovered=$((uncovered + 1))
        uncovered_list="${uncovered_list} ${cap}"
    else
        status="has-pack"
        haspack=$((haspack + 1))
    fi

    printf '%-30s %-9s %-6s %s\n' "${cap}" "${pcount}" "${cases}" "${status}"
done

echo "---"
echo "behavioral-pack coverage: ${haspack} have a pack, ${uncovered} uncovered (of ${total} skill-execution capabilities, threshold=${THRESHOLD} probabilistic THEN clauses)"
if [ "${uncovered}" -gt 0 ]; then
    echo "uncovered (no behavioral eval pack):${uncovered_list}"
    echo "  -> add tests/fixtures/<cap>/evals/behavioral.json, or accept the gap. Advisory only."
fi

if [ "${STRICT}" -eq 1 ] && [ "${uncovered}" -gt 0 ]; then
    exit 1
fi
exit 0
