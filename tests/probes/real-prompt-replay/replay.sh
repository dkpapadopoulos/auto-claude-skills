#!/bin/bash
# replay.sh <skill> <prompts.jsonl> <out-dir>
#
# Replays prompts (from extract.py or routed.py) against one skill's triggers in
# config/default-triggers.json, with the activation hook's own matching: the prompt is
# lowercased with tr, tested with bash `[[ $P =~ $trigger ]]`, and a hit counts only when
# the hook would count it, i.e. at least one match touches a word boundary (a match
# interior to a word on both sides, like "hang" in "changes", scores 0 in the hook and is
# counted here as discarded). It measures TRIGGER MATCHES, not selection: the hook's early
# exits (short prompts, slash commands, greetings, notifications) and scoring are not
# applied.
#
# Prints the prompt count per source, a hit count per trigger index (with the human share),
# the discarded in-word hits, and the prompts that hit any trigger. Writes
# <out-dir>/matches.tsv: indices, source, date, project, prompt (tabs and newlines replaced
# by spaces). The output holds prompt text, so an output directory inside a git work tree
# is refused (exit 2). Exit 2 also for an unknown skill or a malformed prompts file.
set -uf
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
SKILL="${1:-}"; PROMPTS="${2:-}"; OUTDIR="${3:-}"
if [ -z "${SKILL}" ] || [ ! -f "${PROMPTS}" ] || [ -z "${OUTDIR}" ]; then
    echo "usage: replay.sh <skill> <prompts.jsonl> <out-dir>" >&2
    exit 2
fi

# _in_work_tree <existing dir>: prints the work tree containing it, if any. Falls back to
# this checkout, compared case-insensitively, when git cannot answer.
_in_work_tree() {
    local _top _lc_dir _lc_root
    _top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" && [ -n "${_top}" ] && {
        printf '%s' "${_top}"; return 0; }
    _lc_dir="$(printf '%s/' "$1" | tr '[:upper:]' '[:lower:]')"
    _lc_root="$(printf '%s/' "${ROOT}" | tr '[:upper:]' '[:lower:]')"
    case "${_lc_dir}" in "${_lc_root}"*) printf '%s' "${ROOT}"; return 0 ;; esac
    return 1
}
_refuse() {
    echo "refusing to write prompt text inside a git work tree ($1): ${OUTDIR}" >&2
    exit 2
}
# Check the nearest existing ancestor before creating anything, then the created directory
# itself (its last component may be a symlink into a repository).
_probe="${OUTDIR}"
while [ ! -d "${_probe}" ]; do
    _next="$(dirname "${_probe}")"
    [ "${_next}" = "${_probe}" ] && break
    _probe="${_next}"
done
_probe="$(cd "${_probe}" 2>/dev/null && pwd -P)" || { echo "cannot resolve ${OUTDIR}" >&2; exit 2; }
_tree="$(_in_work_tree "${_probe}")" && _refuse "${_tree}"

N_TRIG="$(jq -r --arg s "${SKILL}" '[.skills[] | select(.name == $s) | .triggers | length] | .[0] // empty' \
    "${ROOT}/config/default-triggers.json" 2>/dev/null)"
if [ -z "${N_TRIG}" ]; then
    echo "unknown skill: ${SKILL}" >&2
    exit 2
fi
_bad="$(jq -r 'if type == "object" and (.prompt | type) == "string" then empty else "bad" end' "${PROMPTS}" 2>&1)"
_rc=$?
if [ "${_rc}" -ne 0 ] || [ -n "${_bad}" ]; then
    echo "malformed prompts file (every line must be an object with a string .prompt): ${PROMPTS}" >&2
    exit 2
fi
TRIGGERS=()
while IFS= read -r _t; do
    TRIGGERS+=("${_t}")
done < <(jq -r --arg s "${SKILL}" '.skills[] | select(.name == $s) | .triggers[]' "${ROOT}/config/default-triggers.json")

mkdir -p "${OUTDIR}" || exit 2
_full="$(cd "${OUTDIR}" && pwd -P)" || exit 2
_tree="$(_in_work_tree "${_full}")" && _refuse "${_tree}"
MATCHES="${_full}/matches.tsv"
if [ -L "${MATCHES}" ]; then
    echo "refusing to write through a symlink: ${MATCHES}" >&2
    exit 2
fi
: > "${MATCHES}"

# _hook_hit <P> <trigger>: exit 0 when the hook's scan would score the trigger above 0.
# Mirrors the positional scan in hooks/skill-activation-hook.sh::_score_skills.
_hook_hit() {
    local P="$1" trigger="$2" _scan="$1" _offset=0 matched _pre _abs _aft _left_ok _right_ok _skip
    [[ "$P" =~ $trigger ]] || return 2
    while true; do
        matched="${BASH_REMATCH[0]}"
        [[ -z "$matched" ]] && break
        _pre="${_scan%%"$matched"*}"
        _abs=$((_offset + ${#_pre}))
        _aft=$((_abs + ${#matched}))
        _left_ok=1
        [[ "$_abs" -gt 0 ]] && [[ "${P:$((_abs-1)):1}" =~ [a-z0-9_.] ]] && _left_ok=0
        _right_ok=1
        [[ "$_aft" -lt "${#P}" ]] && [[ "${P:${_aft}:1}" =~ [a-z0-9_.] ]] && _right_ok=0
        if [[ "$_left_ok" -eq 1 ]] || [[ "$_right_ok" -eq 1 ]]; then
            return 0
        fi
        _skip=$((${#_pre} + 1))
        _scan="${_scan:${_skip}}"
        _offset=$((_offset + _skip))
        [[ -z "$_scan" ]] && break
        [[ "$_scan" =~ $trigger ]] || break
    done
    return 1
}

COUNTS=(); HUMAN=(); DISCARDED=()
_i=0
while [ "${_i}" -lt "${#TRIGGERS[@]}" ]; do COUNTS[_i]=0; HUMAN[_i]=0; DISCARDED[_i]=0; _i=$((_i + 1)); done
SOURCES=""   # "name=count name=count ..." (bash 3.2: no associative arrays)
_bump_source() {
    local _name="$1" _out="" _found=0 _pair
    for _pair in ${SOURCES}; do
        if [ "${_pair%%=*}" = "${_name}" ]; then
            _pair="${_name}=$(( ${_pair#*=} + 1 ))"; _found=1
        fi
        _out="${_out}${_out:+ }${_pair}"
    done
    [ "${_found}" -eq 1 ] || _out="${_out}${_out:+ }${_name}=1"
    SOURCES="${_out}"
}

_total=0; _matched=0; _matched_human=0
US=$'\x1f'
# Records: source US ts US project US prompt NUL. NUL and US are removed from the fields
# first, and sources are made word-safe, so no field can split or shift a record.
while IFS= read -r -d '' _rec; do
    _total=$((_total + 1))
    _src="${_rec%%"${US}"*}"; _rest="${_rec#*"${US}"}"
    _ts="${_rest%%"${US}"*}"; _rest="${_rest#*"${US}"}"
    _proj="${_rest%%"${US}"*}"; _raw="${_rest#*"${US}"}"
    _bump_source "${_src}"
    _p="$(printf '%s' "${_raw}" | tr '[:upper:]' '[:lower:]')"
    _hits=""
    _i=0
    while [ "${_i}" -lt "${#TRIGGERS[@]}" ]; do
        _hook_hit "${_p}" "${TRIGGERS[_i]}"
        case $? in
            0) COUNTS[_i]=$((COUNTS[_i] + 1))
               [ "${_src}" = "human" ] && HUMAN[_i]=$((HUMAN[_i] + 1))
               _hits="${_hits}${_hits:+,}${_i}" ;;
            1) DISCARDED[_i]=$((DISCARDED[_i] + 1)) ;;
        esac
        _i=$((_i + 1))
    done
    if [ -n "${_hits}" ]; then
        _matched=$((_matched + 1))
        [ "${_src}" = "human" ] && _matched_human=$((_matched_human + 1))
        _flat="$(printf '%s' "${_raw}" | tr '\t\n\r' '   ')"
        printf '%s\t%s\t%s\t%s\t%s\n' "${_hits}" "${_src}" "${_ts}" "${_proj}" "${_flat}" >> "${MATCHES}"
    fi
done < <(jq -j '
    def safe: tostring | explode | map(select(. != 0) | if . == 31 or . == 9 or . == 10 then 32 else . end) | implode;
    ((.source // "unlabelled") | safe | gsub("[ =]"; "_")) + ([31] | implode)
    + ((.ts // "") | safe) + ([31] | implode)
    + ((.project // "") | safe) + ([31] | implode)
    + (.prompt | explode | map(select(. != 0)) | implode) + ([0] | implode)' "${PROMPTS}")

echo "prompts ${_total}"
for _pair in ${SOURCES}; do
    echo "source ${_pair%%=*}: ${_pair#*=}"
done
_i=0
while [ "${_i}" -lt "${#TRIGGERS[@]}" ]; do
    echo "trigger ${_i}: ${COUNTS[_i]} (human ${HUMAN[_i]}, in-word discarded ${DISCARDED[_i]})"
    _i=$((_i + 1))
done
echo "matched prompts: ${_matched} (human ${_matched_human})"
echo "matches written to ${MATCHES}"
