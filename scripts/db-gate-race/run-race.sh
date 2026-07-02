#!/bin/bash
# run-race.sh — 3-arm DB-gate decision race orchestrator.
#
# Runs each corpus scenario through arms A0 (no directive), B1 (external-content
# directive), B2 (owned-checklist directive) via the existing behavioral eval
# runner (tests/run-behavioral-evals.sh), tagging artifacts by arm so Task 5's
# scorer can compare pass rates per arm.
#
# Usage:
#   VARIANCE=5 bash scripts/db-gate-race/run-race.sh
#   IDS="defect-missing-index-01 defect-missing-index-02" bash scripts/db-gate-race/run-race.sh
#   DRY_RUN=1 IDS="defect-missing-index-01" bash scripts/db-gate-race/run-race.sh
#
# Environment:
#   VARIANCE   iterations per (scenario, arm) passed to --variance (default: 5)
#   IDS        space-separated scenario ids to restrict the race to (default:
#              all ids in the pack)
#   DRY_RUN    when "1", print the runner invocation that WOULD run for each
#              (arm, scenario) pair and exit without ever calling claude
#
# Bash 3.2 compatible (macOS /bin/bash). No `set -e` — a single failing
# scenario must not abort the rest of the race.

RUNNER="tests/run-behavioral-evals.sh"
PACK="tests/fixtures/db-gate-race/evals/corpus.json"
BASE="tests/fixtures/db-gate-race/review-base.md"
B1_DIRECTIVE="tests/fixtures/db-gate-race/arms/B1-external-content.md"
B2_DIRECTIVE="tests/fixtures/db-gate-race/arms/B2-owned-checklist.md"
OUT="tests/artifacts/db-gate-race"

VARIANCE="${VARIANCE:-5}"
DRY_RUN="${DRY_RUN:-0}"

# -------- preflight --------
command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; exit 1; }

if [ ! -f "${RUNNER}" ]; then
    echo "error: runner script not found: ${RUNNER}" >&2
    exit 1
fi
if [ ! -f "${PACK}" ]; then
    echo "error: pack file not found: ${PACK}" >&2
    exit 1
fi
if [ ! -f "${BASE}" ]; then
    echo "error: skill base not found: ${BASE}" >&2
    exit 1
fi
if [ ! -f "${B1_DIRECTIVE}" ]; then
    echo "error: B1 directive file not found: ${B1_DIRECTIVE}" >&2
    exit 1
fi
if [ ! -f "${B2_DIRECTIVE}" ]; then
    echo "error: B2 directive file not found: ${B2_DIRECTIVE}" >&2
    exit 1
fi

# -------- scenario id selection --------
# IDS env var (space-separated) restricts the race; otherwise all ids from
# the pack are used. This lets a caller sanity-check wiring or run a pilot
# without paying for all 28 scenarios x 3 arms.
if [ -n "${IDS:-}" ]; then
    ids="${IDS}"
else
    ids="$(jq -r '.[].id' "${PACK}")"
fi

# Count ids (word count; ids are whitespace-separated, no spaces in an id).
id_count=0
for _id in ${ids}; do
    id_count=$((id_count + 1))
done

arm_count=3
total_runs=$((id_count * arm_count))

echo "=== db-gate-race plan ==="
echo "ids (${id_count}):"
for _id in ${ids}; do
    echo "  - ${_id}"
done
echo "arms: A0 B1 B2"
echo "variance: ${VARIANCE}"
echo "planned runs: ${id_count} ids x ${arm_count} arms = ${total_runs} runner invocations"
if [ "${DRY_RUN}" = "1" ]; then
    echo "DRY_RUN=1 — no runner invocations will execute, no claude calls"
fi
echo "=========================="

export BEHAVIORAL_EVALS=1

FAIL_COUNT=0
TOTAL_COUNT=0

# run_arm arm_name [--directive-file <path>]
run_arm() {
    arm="$1"
    shift
    dir="${OUT}/${arm}"
    mkdir -p "${dir}"
    for id in ${ids}; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        if [ "${DRY_RUN}" = "1" ]; then
            echo "[DRY_RUN][${arm}] would run: ARTIFACTS_DIR=${dir} SKILL_PATH=${BASE} BEHAVIORAL_EVALS=1 bash ${RUNNER} --scenario ${id} --pack ${PACK} --variance ${VARIANCE} --bare $* --variance-report ${dir}/${id}-variance.md > ${dir}/${id}.log 2>&1"
            continue
        fi
        ARTIFACTS_DIR="${dir}" SKILL_PATH="${BASE}" \
            bash "${RUNNER}" --scenario "${id}" --pack "${PACK}" \
            --variance "${VARIANCE}" --bare "$@" \
            --variance-report "${dir}/${id}-variance.md" \
            >"${dir}/${id}.log" 2>&1
        rc=$?
        if [ "${rc}" -ne 0 ]; then
            echo "[${arm}] ${id} FAILED (exit ${rc}) — see ${dir}/${id}.log"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo "[${arm}] ${id} done (exit ${rc})"
        fi
    done
}

run_arm A0
run_arm B1 --directive-file "${B1_DIRECTIVE}"
run_arm B2 --directive-file "${B2_DIRECTIVE}"

if [ "${DRY_RUN}" = "1" ]; then
    echo "DRY_RUN complete → ${TOTAL_COUNT} planned runner invocations, 0 claude calls"
    exit 0
fi

echo "race complete → ${OUT}"
echo "summary: ${TOTAL_COUNT} runs, ${FAIL_COUNT} failed"
if [ "${FAIL_COUNT}" -gt 0 ]; then
    exit 1
fi
exit 0
