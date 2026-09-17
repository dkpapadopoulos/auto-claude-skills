#!/bin/bash
# replay.sh <skill> <prompts.jsonl> <out-dir>
#
# Replays prompts (from extract.py) against one skill's triggers in
# config/default-triggers.json, with the activation hook's own matching: bash
# `[[ $prompt =~ $trigger ]]` on the lowercased prompt. It measures TRIGGER MATCHES, not
# selection: the hook's early exits (short prompts, slash commands, greetings,
# notifications) and scoring are not applied. Lowercasing uses jq's ascii_downcase, where
# the hook uses tr in the session locale; the two differ only on non-ASCII letters.
#
# Prints the prompt count, a match count per trigger index, and the number of prompts that
# matched any trigger. Writes <out-dir>/matches.tsv: indices, date, project, prompt (tabs
# and newlines replaced by spaces). The output holds prompt text, so an output directory
# inside the repository is refused (exit 2). Exit 2 also for an unknown skill.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
SKILL="${1:-}"; PROMPTS="${2:-}"; OUTDIR="${3:-}"
if [ -z "${SKILL}" ] || [ ! -f "${PROMPTS}" ] || [ -z "${OUTDIR}" ]; then
    echo "usage: replay.sh <skill> <prompts.jsonl> <out-dir>" >&2
    exit 2
fi
case "${OUTDIR}" in /*) _abs="${OUTDIR}" ;; *) _abs="${PWD}/${OUTDIR}" ;; esac
_parent="$(cd "$(dirname "${_abs}")" 2>/dev/null && pwd -P)" || {
    echo "output directory's parent does not exist: ${OUTDIR}" >&2
    exit 2
}
_full="${_parent}/$(basename "${_abs}")"
case "${_full}/" in
    "${ROOT}"/*) echo "refusing to write prompt text inside the repository: ${_full}" >&2; exit 2 ;;
esac

N_TRIG="$(jq -r --arg s "${SKILL}" '[.skills[] | select(.name == $s) | .triggers | length] | .[0] // empty' \
    "${ROOT}/config/default-triggers.json" 2>/dev/null)"
if [ -z "${N_TRIG}" ]; then
    echo "unknown skill: ${SKILL}" >&2
    exit 2
fi
TRIGGERS=()
while IFS= read -r _t; do
    TRIGGERS+=("${_t}")
done < <(jq -r --arg s "${SKILL}" '.skills[] | select(.name == $s) | .triggers[]' "${ROOT}/config/default-triggers.json")

mkdir -p "${_full}"
: > "${_full}/matches.tsv"
COUNTS=()
_i=0
while [ "${_i}" -lt "${#TRIGGERS[@]}" ]; do COUNTS[_i]=0; _i=$((_i + 1)); done

_total=0
_matched=0
US=$'\x1f'
while IFS= read -r -d '' _rec; do
    _total=$((_total + 1))
    _ts="${_rec%%"${US}"*}"; _rest="${_rec#*"${US}"}"
    _proj="${_rest%%"${US}"*}"; _p="${_rest#*"${US}"}"
    _hits=""
    _i=0
    while [ "${_i}" -lt "${#TRIGGERS[@]}" ]; do
        _t="${TRIGGERS[_i]}"
        if [[ "${_p}" =~ ${_t} ]]; then
            COUNTS[_i]=$((COUNTS[_i] + 1))
            _hits="${_hits}${_hits:+,}${_i}"
        fi
        _i=$((_i + 1))
    done
    if [ -n "${_hits}" ]; then
        _matched=$((_matched + 1))
        _flat="$(printf '%s' "${_p}" | tr '\t\n\r' '   ')"
        printf '%s\t%s\t%s\t%s\n' "${_hits}" "${_ts}" "${_proj}" "${_flat}" >> "${_full}/matches.tsv"
    fi
done < <(jq -j '(.ts // "") + "\u001f" + (.project // "") + "\u001f" + ((.prompt // "") | ascii_downcase) + ([0] | implode)' "${PROMPTS}")

echo "prompts ${_total}"
_i=0
while [ "${_i}" -lt "${#TRIGGERS[@]}" ]; do
    echo "trigger ${_i}: ${COUNTS[_i]}"
    _i=$((_i + 1))
done
echo "matched prompts: ${_matched}"
echo "matches written to ${_full}/matches.tsv"
