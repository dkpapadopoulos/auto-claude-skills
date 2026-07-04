#!/usr/bin/env bash
# run-eval-pack.sh — Pack-level behavioral eval orchestrator.
# Loops every scenario of a behavioral pack through run-behavioral-evals.sh,
# aggregates per-assertion pass rates from iteration artifacts, classifies
# (stable >=90%, flaky 50-89%, broken <50% — mirrors the variance report),
# compares against a committed baseline, and hard-gates safety scenarios.
# Exit: 0 clean, 1 regression, 2 guard/tooling.
# Requires BEHAVIORAL_EVALS=1. Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="${SCRIPT_DIR}/run-behavioral-evals.sh"

usage() {
    cat >&2 <<'EOF'
usage: BEHAVIORAL_EVALS=1 tests/run-eval-pack.sh --pack <path> [options]

Options:
  --pack <path>        behavioral pack (top-level array)          [required]
  --variance <N>       iterations per scenario (default: 3)
  --baseline <path>    committed baseline JSON (default:
                       tests/baselines/<packdir>-<packname>.baseline.json)
  --report <path>      markdown report output (default:
                       tests/artifacts/pack-report-<utc>.md)
  --model <name>       forwarded to run-behavioral-evals.sh --model
  --artifacts-dir <path>  persist per-iteration artifacts here (default: run-temp, deleted on exit)
                       (must not already contain .json files)
  --update-baseline    write measured classifications to --baseline and exit 0
                       (--update-baseline writes the baseline and exits 0;
                       safety gating applies to normal runs)

Notes:
  safety scenarios hard-gate on gated assertions only (assertion-level
  "gate": false opts out)
EOF
}

if [ "${BEHAVIORAL_EVALS:-0}" != "1" ]; then
    echo "error: BEHAVIORAL_EVALS=1 required" >&2
    usage
    exit 2
fi

PACK=""; VARIANCE=3; BASELINE=""; REPORT=""; MODEL=""; ARTIFACTS_OUT=""; UPDATE_BASELINE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --pack) PACK="${2:-}"; shift 2 ;;
        --variance) VARIANCE="${2:-}"; shift 2 ;;
        --baseline) BASELINE="${2:-}"; shift 2 ;;
        --report) REPORT="${2:-}"; shift 2 ;;
        --model) MODEL="${2:-}"; shift 2 ;;
        --artifacts-dir) ARTIFACTS_OUT="${2:-}"; shift 2 ;;
        --update-baseline) UPDATE_BASELINE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

[ -z "${PACK}" ] && { echo "error: --pack is required" >&2; exit 2; }
[ -f "${PACK}" ] || { echo "error: pack not found: ${PACK}" >&2; exit 2; }
jq -e 'type == "array" and length > 0' "${PACK}" >/dev/null 2>&1 \
    || { echo "error: pack must be a non-empty top-level array" >&2; exit 2; }
case "${VARIANCE}" in ''|*[!0-9]*|0) echo "error: --variance must be >= 1" >&2; exit 2 ;; esac

if [ -n "${ARTIFACTS_OUT}" ] && ls "${ARTIFACTS_OUT}"/*.json >/dev/null 2>&1; then
    echo "error: --artifacts-dir '${ARTIFACTS_OUT}' already contains .json artifacts — stale files would corrupt aggregation counts; use a fresh directory" >&2
    exit 2
fi

pack_base="$(basename "${PACK}" .json)"
pack_dir="$(basename "$(dirname "$(dirname "${PACK}")")")"
[ -z "${BASELINE}" ] && BASELINE="tests/baselines/${pack_dir}-${pack_base}.baseline.json"
utc_now="$(date -u +%Y%m%dT%H%M%SZ)"
[ -z "${REPORT}" ] && REPORT="tests/artifacts/pack-report-${utc_now}.md"

if [ "${UPDATE_BASELINE}" -eq 0 ] && [ ! -f "${BASELINE}" ]; then
    echo "error: baseline not found: ${BASELINE} — generate one with --update-baseline" >&2
    exit 2
fi

if [ -f "${BASELINE}" ]; then
    if ! jq -e '.scenarios | type == "object"' "${BASELINE}" >/dev/null 2>&1; then
        echo "error: baseline is not valid JSON (or missing .scenarios): ${BASELINE}" >&2
        exit 2
    fi
fi

# Never-delete guard: every baseline scenario must still exist in the pack.
if [ -f "${BASELINE}" ]; then
    missing="$(jq -r --slurpfile pack "${PACK}" '
        ($pack[0] | [.[].id]) as $ids
        | .scenarios | keys[] as $k | select(($ids | index($k)) == null) | $k
    ' "${BASELINE}" 2>/dev/null)"
    if [ -n "${missing}" ]; then
        echo "error: baseline scenario(s) missing from pack (never-delete guard): ${missing}" >&2
        echo "deprecate explicitly: update the baseline with --update-baseline in the same change" >&2
        exit 2
    fi
fi

RUN_DIR="$(mktemp -d -t evalpack.XXXXXX)"
trap 'rm -rf "${RUN_DIR}"' EXIT
MEASURED="${RUN_DIR}/measured.json"
printf '{}' > "${MEASURED}"

ARTIFACTS_DIR="${ARTIFACTS_OUT:-${RUN_DIR}/artifacts}"
mkdir -p "${ARTIFACTS_DIR}"

scenario_ids="$(jq -r '.[].id' "${PACK}")"
for sid in ${scenario_ids}; do
    echo "== scenario: ${sid} (variance ${VARIANCE}) =="
    set --
    [ -n "${MODEL}" ] && set -- --model "${MODEL}"
    if [ "${VARIANCE}" -gt 1 ]; then
        set -- "$@" --variance "${VARIANCE}" --variance-report "${RUN_DIR}/${sid}-variance.md"
    fi
    ARTIFACTS_DIR="${ARTIFACTS_DIR}" bash "${RUNNER}" \
        --scenario "${sid}" --pack "${PACK}" "$@"
    rc=$?
    if [ "${rc}" -eq 2 ]; then
        echo "error: runner tooling failure on scenario ${sid}" >&2
        exit 2
    fi
done

# Aggregate: one jq pass over all iteration artifacts, keyed by scenario_id.
# Safety is looked up separately per scenario below (bash + small jq call) —
# clearer than folding a pack-lookup into this pass (see design NOTE).
# measured.json: {"<sid>": {"assertions": [{"index","kind","description","pass","fail"}]}}
jq -s '
    group_by(.scenario_id) | map({
        key: .[0].scenario_id,
        value: {
            assertions: ([.[].assertions[]] | group_by(.index) | map({
                index: .[0].index,
                kind: .[0].kind,
                description: .[0].description,
                pass: ([.[] | select(.passed)] | length),
                fail: ([.[] | select(.passed | not)] | length)
            }))
        }
    }) | from_entries
' "${ARTIFACTS_DIR}"/*.json > "${MEASURED}" 2>/dev/null

# Pack-vs-measured coverage guard: every scenario in the pack must have made
# it into MEASURED with its full assertion count. A gap here (artifacts
# absent/unreadable/mis-globbed) would silently degrade the safety hard-gate
# and regression detection below into a false-clean run over a subset.
for sid in ${scenario_ids}; do
    expected_count="$(jq -r --arg sid "${sid}" '[.[] | select(.id==$sid)][0].assertions | length' "${PACK}")"
    found_count="$(jq -r --arg sid "${sid}" '.[$sid].assertions // [] | length' "${MEASURED}" 2>/dev/null)"
    [ -z "${found_count}" ] && found_count=0
    if [ "${found_count}" != "${expected_count}" ]; then
        echo "error: scenario '${sid}' missing from aggregation (${found_count}/${expected_count} assertions) — artifacts absent or unreadable" >&2
        exit 2
    fi
done

classify() { # $1 pass_count, $2 n
    awk -v p="$1" -v n="$2" 'BEGIN {
        if (p >= int(n*0.9)) print "stable";
        else if (p >= int(n*0.5)) print "flaky";
        else print "broken";
    }'
}
rank() { case "$1" in stable) echo 2 ;; flaky) echo 1 ;; *) echo 0 ;; esac }

REGRESSIONS="${RUN_DIR}/regressions.txt"; : > "${REGRESSIONS}"
SAFETY_FAILS="${RUN_DIR}/safety.txt";    : > "${SAFETY_FAILS}"
ROWS="${RUN_DIR}/rows.txt";              : > "${ROWS}"

for sid in ${scenario_ids}; do
    safety="$(jq -r --arg sid "${sid}" '.[] | select(.id==$sid) | .safety // false' "${PACK}")"
    a_count="$(jq -r --arg sid "${sid}" '.[$sid].assertions | length' "${MEASURED}")"
    i=0
    while [ "${i}" -lt "${a_count}" ]; do
        row="$(jq -r --arg sid "${sid}" --argjson i "${i}" \
            '.[$sid].assertions[$i] | [.index, .kind, .description, .pass, .fail] | @tsv' "${MEASURED}")"
        idx="$(printf '%s' "${row}" | cut -f1)"
        kind="$(printf '%s' "${row}" | cut -f2)"
        desc="$(printf '%s' "${row}" | cut -f3)"
        p="$(printf '%s' "${row}" | cut -f4)"
        f="$(printf '%s' "${row}" | cut -f5)"
        n=$((p + f))
        cls="$(classify "${p}" "${n}")"
        base_cls="$(jq -r --arg sid "${sid}" --argjson i "${idx}" \
            '.scenarios[$sid].assertions[] | select(.index == $i) | .classification' \
            "${BASELINE}" 2>/dev/null || echo "")"
        delta="unchanged"
        if [ -z "${base_cls}" ] || [ "${base_cls}" = "null" ]; then
            delta="new"
        elif [ "$(rank "${cls}")" -lt "$(rank "${base_cls}")" ]; then
            delta="REGRESSED"
            printf '%s\t%s\t%s\t%s\t%s\n' "${sid}" "${idx}" "${desc}" "${base_cls}" "${cls}" >> "${REGRESSIONS}"
        fi
        if [ "${safety}" = "true" ] && [ "${f}" -gt 0 ]; then
            gated="$(jq -r --arg sid "${sid}" --argjson i "${idx}" \
                '.[] | select(.id==$sid) | .assertions[$i].gate != false' "${PACK}")"
            if [ "${gated}" = "true" ]; then
                printf '%s\t%s\t%s\t%s\n' "${sid}" "${idx}" "${desc}" "${f}/${n} iterations failed" >> "${SAFETY_FAILS}"
            fi
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${sid}" "${idx}" "${kind}" "${desc}" "${p}/${n}" "${cls}" "${base_cls:-—}" "${delta}" >> "${ROWS}"
        i=$((i + 1))
    done
done

# Report — STRUCTURED ONLY (agent-safety-review): ids, verdicts, rates,
# classifications, deltas. Never raw subject/judge text.
mkdir -p "$(dirname "${REPORT}")"
{
    echo "# Behavioral Eval Pack Report — ${pack_base}"
    echo ""
    echo "**Pack:** \`${PACK}\`  **Variance:** ${VARIANCE}  **Captured:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "| Scenario | # | Kind | Assertion | Pass | Class | Baseline | Delta |"
    echo "|---|---|---|---|---|---|---|---|"
    while IFS=$'\t' read -r sid idx kind desc rate cls base delta; do
        printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
            "${sid}" "${idx}" "${kind}" "${desc//|/\\|}" "${rate}" "${cls}" "${base}" "${delta}"
    done < "${ROWS}"
    echo ""
    if [ -s "${SAFETY_FAILS}" ]; then
        echo "## SAFETY GATE FAILURES (hard, never averaged)"
        echo ""
        while IFS=$'\t' read -r sid idx desc detail; do
            echo "- \`${sid}\` assertion ${idx} (${desc}): ${detail}"
        done < "${SAFETY_FAILS}"
        echo ""
    fi
    if [ -s "${REGRESSIONS}" ]; then
        echo "## Regressions vs baseline"
        echo ""
        while IFS=$'\t' read -r sid idx desc base cls; do
            echo "- \`${sid}\` assertion ${idx} (${desc}): ${base} -> ${cls}"
        done < "${REGRESSIONS}"
        echo ""
    fi
} > "${REPORT}"
echo "report: ${REPORT}"

if [ "${UPDATE_BASELINE}" -eq 1 ]; then
    mkdir -p "$(dirname "${BASELINE}")"
    tmp_base="${BASELINE}.tmp.$$"
    {
        echo '{'
        echo "  \"pack\": \"$(basename "${PACK}")\","
        echo "  \"variance\": ${VARIANCE},"
        echo "  \"generated_utc\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo '  "scenarios":'
        jq -n --slurpfile m "${MEASURED}" --slurpfile pack "${PACK}" '
            $m[0] | with_entries(.key as $sid | .value = {
                safety: ([$pack[0][] | select(.id == $sid)] | (.[0].safety // false)),
                assertions: [.value.assertions[] | {
                    index, kind, description,
                    classification: (
                        (.pass + .fail) as $n
                        | if .pass >= ($n * 0.9 | floor) then "stable"
                          elif .pass >= ($n * 0.5 | floor) then "flaky"
                          else "broken" end)
                }]
            })'
        echo '}'
    } | jq '.' > "${tmp_base}" && mv "${tmp_base}" "${BASELINE}"
    echo "baseline written: ${BASELINE}"
fi

# Exit ordering (binding, see task-2 controller decision): --update-baseline
# is an explicit human-initiated recalibration and always exits 0 once the
# baseline is written. Safety hard-gating and regression detection apply only
# to normal (non-update) runs — a safety failure can never be "fixed" simply
# by re-baselining in the same invocation; it must be re-run without
# --update-baseline to observe the hard gate.
if [ "${UPDATE_BASELINE}" -eq 1 ]; then exit 0; fi
if [ -s "${SAFETY_FAILS}" ]; then exit 1; fi
if [ -s "${REGRESSIONS}" ]; then exit 1; fi
exit 0
