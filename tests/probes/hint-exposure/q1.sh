#!/bin/bash
# q1.sh <variants.json> <base-config.json> <draw-dir>
#
# The #412 Q1 replay (pre-registration D4). For each route and variant in the appendix it
# writes <draw-dir>/cfg-<route>-<variant>.json, the base config with ONLY that route's
# .triggers replaced by the appendix's array, and replays <draw-dir>/prompts.jsonl through
# tests/probes/real-prompt-replay/replay.sh --config into <draw-dir>/replay-<route>-<variant>/,
# whose hits.tsv score.py reads. replay.sh refuses a draw dir inside a git repository.
# Exit 0 when every replay ran, 2 on bad input or a failed replay.
set -uf
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
VARIANTS="${1:-}"; BASE="${2:-}"; DRAW="${3:-}"
if [ ! -f "${VARIANTS}" ] || [ ! -f "${BASE}" ] || [ ! -f "${DRAW}/prompts.jsonl" ]; then
    echo "usage: q1.sh <variants.json> <base-config.json> <draw-dir with prompts.jsonl>" >&2
    exit 2
fi
_pairs="$(jq -r '.routes | to_entries[] | .key as $r | .value.kind as $k
    | ("V0", "V1", "V2") as $v | "\($r)\t\($k)\t\($v)"' "${VARIANTS}" 2>/dev/null)" || {
    echo "unreadable variants file: ${VARIANTS}" >&2; exit 2; }
while IFS="$(printf '\t')" read -r _route _kind _v; do
    [ -n "${_route}" ] || continue
    case "${_kind}" in
        skill) _list=skills ;;
        hint) _list=methodology_hints ;;
        *) echo "route ${_route}: kind must be skill or hint, not '${_kind}'" >&2; exit 2 ;;
    esac
    _cfg="${DRAW}/cfg-${_route}-${_v}.json"
    jq --arg r "${_route}" --arg l "${_list}" --arg v "${_v}" --slurpfile var "${VARIANTS}" \
        '(.[$l][] | select(.name == $r) | .triggers) = $var[0].routes[$r][$v]' "${BASE}" > "${_cfg}" || exit 2
    bash "${ROOT}/tests/probes/real-prompt-replay/replay.sh" --config "${_cfg}" "${_route}" \
        "${DRAW}/prompts.jsonl" "${DRAW}/replay-${_route}-${_v}" > "${DRAW}/replay-${_route}-${_v}.log" 2>&1 < /dev/null || {
        echo "replay failed for ${_route} ${_v}; see ${DRAW}/replay-${_route}-${_v}.log" >&2; exit 2; }
    echo "${_route} ${_v}: $(grep -c . "${DRAW}/replay-${_route}-${_v}/hits.tsv") of $(grep -c . "${DRAW}/prompts.jsonl") prompts matched"
done <<EOF
${_pairs}
EOF
