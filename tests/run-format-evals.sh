#!/usr/bin/env bash
# run-format-evals.sh — Format-handoff eval driver: ranks F1 (markdown),
# F2 (markdown + YAML front-matter), F3 (DocLang XML) renderings of real PDLC
# artifacts on comprehension / fabrication / drift-detection pass rates.
# Delegates each (scenario × format) combo to tests/run-behavioral-evals.sh.
# Opt-in: requires BEHAVIORAL_EVALS=1 (enforced by the inner runner too).
# Bash 3.2 compatible.
#
# Env:
#   FORMATS    space-separated subset of "f1 f2 f3" (default: all three)
#   VARIANCE   iterations per combo (default: 3)
#   SCENARIOS  space-separated subset of scenario ids (default: all six)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACK="${ROOT}/tests/fixtures/format-eval/evals/format-eval.json"
REND="${ROOT}/tests/fixtures/format-eval/renderings"
OUT="${ROOT}/tests/artifacts/format-eval"
VARIANCE="${VARIANCE:-3}"
FORMATS="${FORMATS:-f1 f2 f3}"
# BARE=1 passes --bare to the inner runner. Default 0: as of Claude CLI
# 2026-06, `claude -p --bare` fails auth ("Not logged in") in nested sessions.
# Ambient banner noise is constant across formats, so ranking stays valid.
BARE="${BARE:-0}"
SCENARIOS="${SCENARIOS:-spec-probes proposal-probes design-probes postmortem-probes design-drift spec-drift}"

if [ "${BEHAVIORAL_EVALS:-0}" != "1" ]; then
    echo "error: BEHAVIORAL_EVALS=1 required (this driver spends real claude -p calls)" >&2
    exit 2
fi
mkdir -p "${OUT}"

# scenario id -> artifact whose rendering is injected
artifact_for() {
    case "$1" in
        spec-probes|spec-drift)   echo "spec" ;;
        proposal-probes)          echo "proposal" ;;
        design-probes|design-drift) echo "design" ;;
        postmortem-probes)        echo "postmortem" ;;
        *)                        echo "" ;;
    esac
}

FAILURES=0
for fmt in ${FORMATS}; do
    ext="md"
    [ "${fmt}" = "f3" ] && ext="dclg.xml"
    for scenario in ${SCENARIOS}; do
        artifact="$(artifact_for "${scenario}")"
        if [ -z "${artifact}" ]; then
            echo "skip: unknown scenario '${scenario}'" >&2
            continue
        fi
        rendering="${REND}/${artifact}.${fmt}.${ext}"
        if [ ! -f "${rendering}" ]; then
            echo "skip: missing rendering ${rendering}" >&2
            FAILURES=$((FAILURES + 1))
            continue
        fi
        echo "== ${scenario} x ${fmt}  (${rendering##*/}, variance ${VARIANCE})"
        # Per-format ARTIFACTS_DIR: the inner runner names per-iteration
        # artifact JSONs <scenario>-<UTC-second>-iterN.json, so concurrent
        # per-format runs of the same scenario would otherwise collide on
        # identical paths (counter files are mktemp'd and cannot race).
        BARE_ARG=""
        [ "${BARE}" = "1" ] && BARE_ARG="--bare"
        SKILL_PATH="${rendering}" ARTIFACTS_DIR="${OUT}/raw-${fmt}" \
            bash "${ROOT}/tests/run-behavioral-evals.sh" \
            --pack "${PACK}" --scenario "${scenario}" \
            --variance "${VARIANCE}" --variance-report "${OUT}/${scenario}.${fmt}.md" \
            ${BARE_ARG} || FAILURES=$((FAILURES + 1))
    done
done

# -------- aggregate: per (format, assertion-kind) pass rates --------
# Reports are markdown tables; assertion kind is embedded as a [tag] prefix in
# each description. Fabrication rate = 1 - absence pass rate.
echo ""
echo "== AGGREGATE (variance ${VARIANCE}) =="
printf '%-4s %-15s %6s %6s %10s\n' fmt kind pass fail pass_rate
for fmt in ${FORMATS}; do
    for kind in comprehension absence drift; do
        pass_total=0
        fail_total=0
        for report in "${OUT}"/*."${fmt}".md; do
            [ -f "${report}" ] || continue
            counts="$(awk -F'|' -v k="[${kind}]" '
                index($3, k) { p += $4; f += $5 }
                END { printf "%d %d", p+0, f+0 }' "${report}")"
            pass_total=$((pass_total + ${counts%% *}))
            fail_total=$((fail_total + ${counts##* }))
        done
        total=$((pass_total + fail_total))
        if [ "${total}" -gt 0 ]; then
            rate="$(awk -v p="${pass_total}" -v t="${total}" 'BEGIN { printf "%.0f%%", (p/t)*100 }')"
        else
            rate="—"
        fi
        printf '%-4s %-15s %6d %6d %10s\n' "${fmt}" "${kind}" "${pass_total}" "${fail_total}" "${rate}"
    done
done

exit "$([ "${FAILURES}" -eq 0 ] && echo 0 || echo 1)"
