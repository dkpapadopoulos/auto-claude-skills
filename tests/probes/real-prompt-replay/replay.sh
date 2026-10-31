#!/bin/bash
# replay.sh [--config FILE] <skill-or-hint> <prompts.jsonl> <out-dir>
#
# Replays prompts (from extract.py or routed.py) against the triggers of one skill
# (.skills[]) or one methodology hint (.methodology_hints[]) in config/default-triggers.json,
# or in FILE (a variant config, #412), with the activation hook's own matching: the prompt is
# lowercased with tr and tested with bash `[[ $P =~ $trigger ]]`. For a skill a hit counts
# only when the hook would count it, i.e. at least one match touches a word boundary (a match
# interior to a word on both sides, like "hang" in "changes", scores 0 in the hook and is
# counted here as discarded). For a hint any match counts, as in the hook's METHODOLOGY HINTS
# loop, which has no such scan. It measures TRIGGER MATCHES, not selection: the hook's early
# exits (short prompts, slash commands, greetings, notifications), scoring, a hint's phase
# scope and its suppression by a selected skill are not applied.
#
# Prints "kind skill" or "kind hint", the prompt count per source, a hit count per trigger
# index (with the human share), the discarded in-word hits, and the prompts that hit any
# trigger. Writes <out-dir>/matches.tsv: indices, source, date, project, prompt (tabs and
# newlines replaced by spaces); and <out-dir>/hits.tsv: the 1-based line number of each
# matched record in the prompts file, a tab, and its indices. The output holds prompt text,
# so an output directory inside a git repository, or one git cannot vouch for, is refused
# (exit 2). Exit 2 also for an unknown name, a name that is both a skill and a hint, an
# unreadable config or a malformed prompts file. The hook can also select a skill by its name
# alone; this replay does not model that.
set -uf
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
CONFIG="${ROOT}/config/default-triggers.json"
if [ "${1:-}" = "--config" ]; then
    CONFIG="${2:-}"
    shift 2 2>/dev/null || set --
    if [ -z "${CONFIG}" ] || [ ! -f "${CONFIG}" ] || ! jq -e 'type == "object"' "${CONFIG}" >/dev/null 2>&1; then
        echo "not a readable JSON config: ${CONFIG}" >&2
        exit 2
    fi
fi
SKILL="${1:-}"; PROMPTS="${2:-}"; OUTDIR="${3:-}"
if [ -z "${SKILL}" ] || [ ! -f "${PROMPTS}" ] || [ -z "${OUTDIR}" ]; then
    echo "usage: replay.sh [--config FILE] <skill-or-hint> <prompts.jsonl> <out-dir>" >&2
    exit 2
fi

# _repo_holding <existing dir>: prints the repository containing it and returns 0; returns 1
# when git positively says "not a git repository"; prints a reason and returns 2 when git
# cannot answer. Only 1 lets the script write.
_repo_holding() {
    local _out _rc
    command -v git >/dev/null 2>&1 || { printf 'git is unavailable'; return 2; }
    _out="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_CEILING_DIRECTORIES \
        -u GIT_DISCOVERY_ACROSS_FILESYSTEM LC_ALL=C git -C "$1" rev-parse --absolute-git-dir 2>&1)"
    _rc=$?
    if [ "${_rc}" -eq 0 ]; then printf '%s' "${_out}"; return 0; fi
    # Git stops at a mount point unless told otherwise, and says so. That answers nothing
    # about the parents above it (on Linux /tmp is often its own filesystem), so retry.
    case "${_out}" in
        "fatal: not a git repository (or any parent up to mount point"*)
            _out="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_CEILING_DIRECTORIES \
                GIT_DISCOVERY_ACROSS_FILESYSTEM=1 LC_ALL=C git -C "$1" rev-parse --absolute-git-dir 2>&1)"
            _rc=$?
            if [ "${_rc}" -eq 0 ]; then printf '%s' "${_out}"; return 0; fi
            ;;
    esac
    # Only the full-search form means "no repository", and only at the START of the
    # message: a broken .git file or a filesystem boundary also say "not a git repository"
    # while stopping the search early, and the same words can appear inside a printed path.
    case "${_out}" in "fatal: not a git repository (or any of the parent directories)"*) return 1 ;; esac
    local _nl=$'\n'
    printf 'git could not tell: %s' "${_out##*${_nl}}"
    return 2
}
case "/${OUTDIR}/" in
    */../*) echo "refusing an output path with a '..' component: ${OUTDIR}" >&2; exit 2 ;;
esac
# Check the nearest existing ancestor before creating anything. Every component below it is
# created here as a plain directory, so it cannot lead into a repository (short of a
# concurrent swap: this guards against mistakes, not against an attacker on your machine).
_probe="${OUTDIR}"
while [ ! -d "${_probe}" ]; do
    _next="$(dirname "${_probe}")"
    [ "${_next}" = "${_probe}" ] && break
    _probe="${_next}"
done
_probe="$(cd "${_probe}" 2>/dev/null && pwd -P)" || { echo "cannot resolve ${OUTDIR}" >&2; exit 2; }
_why="$(_repo_holding "${_probe}")"
case $? in
    0) echo "refusing to write prompt text inside a git repository (${_why}): ${OUTDIR}" >&2; exit 2 ;;
    1) ;;
    *) echo "refusing to write: cannot check that ${OUTDIR} is outside a git repository: ${_why}" >&2; exit 2 ;;
esac

# KIND: "skill" or "hint", from which list names it; both or neither is refused.
KIND="$(jq -r --arg s "${SKILL}" '
    [(.skills // [])[] | select(.name == $s)] as $k | [(.methodology_hints // [])[] | select(.name == $s)] as $h
    | if ($k | length) > 0 and ($h | length) > 0 then "both"
      elif ($k | length) > 0 then "skill" elif ($h | length) > 0 then "hint" else "" end' "${CONFIG}" 2>/dev/null)"
case "${KIND}" in
    skill) LIST="skills" ;;
    hint) LIST="methodology_hints" ;;
    both) echo "ambiguous name, both a skill and a methodology hint: ${SKILL}" >&2; exit 2 ;;
    *) echo "unknown skill or hint: ${SKILL}" >&2; exit 2 ;;
esac
_bad="$(jq -r 'if type == "object" and (.prompt | type) == "string" then empty else "bad" end' "${PROMPTS}" 2>&1)"
_rc=$?
if [ "${_rc}" -ne 0 ] || [ -n "${_bad}" ]; then
    echo "malformed prompts file (every line must be an object with a string .prompt): ${PROMPTS}" >&2
    exit 2
fi
TRIGGERS=()
while IFS= read -r _t; do
    TRIGGERS+=("${_t}")
done < <(jq -r --arg s "${SKILL}" --arg l "${LIST}" '.[$l][] | select(.name == $s) | (.triggers // [])[]' "${CONFIG}")

mkdir -p "${OUTDIR}" || exit 2
_full="$(cd "${OUTDIR}" && pwd -P)" || exit 2
MATCHES="${_full}/matches.tsv"
HITS="${_full}/hits.tsv"
for _f in "${MATCHES}" "${HITS}"; do
    if [ -L "${_f}" ] || { [ -e "${_f}" ] && [ -n "$(find "${_f}" -links +1 2>/dev/null)" ]; }; then
        echo "refusing to write through a symlink or hard link: ${_f}" >&2
        exit 2
    fi
done
# Replace, never write through: remove the old files, then create them exclusively
# (noclobber makes bash open with O_EXCL) and keep them open for the whole run.
rm -f "${MATCHES}" "${HITS}" || exit 2
set -C
{ exec 3> "${MATCHES}"; } 2>/dev/null || { echo "cannot create ${MATCHES} exclusively" >&2; exit 2; }
{ exec 4> "${HITS}"; } 2>/dev/null || { echo "cannot create ${HITS} exclusively" >&2; exit 2; }
set +C
chmod 600 "${MATCHES}" "${HITS}"

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
        if [ "${KIND}" = "hint" ]; then
            # The hook's hint loop: any match counts.
            [[ "${_p}" =~ ${TRIGGERS[_i]} ]] && _rc=0 || _rc=2
        else
            _hook_hit "${_p}" "${TRIGGERS[_i]}"; _rc=$?
        fi
        case ${_rc} in
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
        printf '%s\t%s\t%s\t%s\t%s\n' "${_hits}" "${_src}" "${_ts}" "${_proj}" "${_flat}" >&3
        printf '%s\t%s\n' "${_total}" "${_hits}" >&4
    fi
done < <(jq -j '
    def safe: tostring | explode | map(select(. != 0) | if . == 31 or . == 9 or . == 10 then 32 else . end) | implode;
    ((.source // "unlabelled") | safe | gsub("[ =]"; "_")) + ([31] | implode)
    + ((.ts // "") | safe) + ([31] | implode)
    + ((.project // "") | safe) + ([31] | implode)
    + (.prompt | explode | map(select(. != 0)) | implode) + ([0] | implode)' "${PROMPTS}")

echo "kind ${KIND}"
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
