#!/usr/bin/env bash
# test-real-prompt-replay.sh — the real-prompt replay probe (tests/probes/real-prompt-replay/)
# estimates how often a skill's triggers fire on prompts from real sessions. Its numbers are
# only as good as the extraction, so this pins: how each prompt is labelled (from the
# transcript's provenance fields, not its wording), that the replay matches like the hook
# (tr lowercasing, bash =~, the in-word discard), that record framing survives NUL/US/tab,
# that live routings are paired through parentUuid, and that no script writes prompt text
# into any git repository, or anywhere git cannot vouch for.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-real-prompt-replay.sh ==="

PROBE="${PROJECT_ROOT}/tests/probes/real-prompt-replay"
EXTRACT="${PROBE}/extract.py"
REPLAY="${PROBE}/replay.sh"
ROUTED="${PROBE}/routed.py"
for _f in "${EXTRACT}" "${REPLAY}" "${ROUTED}"; do
    if [ ! -f "${_f}" ]; then
        _record_fail "probe script exists: ${_f##*/}" "missing ${_f}"
        print_summary
        exit 1
    fi
done

# has_line <description> <exact line> <text>: the text contains that exact line.
has_line() {
    if printf '%s\n' "$3" | grep -qxF -- "$2"; then
        _record_pass "$1"
    else
        _record_fail "$1" "no line '$2' in: $3"
    fi
}
# no_file <description> <path>
no_file() {
    if [ -e "$2" ] || [ -L "$2" ]; then _record_fail "$1" "exists: $2"; else _record_pass "$1"; fi
}
# mode_of <path>: the permission bits, as python prints them (0o600).
mode_of() {
    python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}
# source_of_prompt <jsonl> <prompt prefix>: the .source of the first record starting with it.
source_of_prompt() {
    jq -r --arg p "$2" 'select(.prompt | startswith($p)) | .source' "$1" | head -1
}

setup_test_env
PROJ="${TEST_TMPDIR}/projects"
USPROJ="p"$'\x1f'"us"
mkdir -p "${PROJ}/p1/s1/subagents" "${PROJ}/p2" "${PROJ}/${USPROJ}"
HUMAN='origin:{kind:"human"},promptSource:"typed",entrypoint:"cli"'
u() { jq -nc --arg t "$1" --arg c "$2" "{type:\"user\",timestamp:\$t,message:{role:\"user\",content:\$c},$3}"; }
CAPS=$'ASK A FEW OF THEM SEPARATELY AND GIVE ME THE RAW ANSWERS\n\n'
BOTH="ask codex and gemini the same question and show me both raw answers"
{
    u "2026-09-17T10:00:00Z" "${CAPS}" "${HUMAN}"
    u "2026-09-17T10:00:30Z" "${CAPS}" "${HUMAN}"
    u "2026-09-17T10:01:00Z" "${BOTH}" 'promptSource:"sdk",entrypoint:"sdk-py"'
    u "2026-09-17T10:01:30Z" "${BOTH}" "${HUMAN}"
    u "2026-09-17T10:01:40Z" "pipeline: run the nightly checks" 'promptSource:"sdk",entrypoint:"sdk-cli"'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:02:00Z",origin:{kind:"human"},message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"x"},{type:"text",text:"tool output: give me both of them raw answers"}]}}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:03:00Z",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:null},{type:"text",text:"fix the login bug in the auth service"}]}}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:03:10Z",message:null}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:03:20Z",message:{role:"user",content:[{type:"text",text:null}]}}'
    u "2026-09-17T10:04:00Z" "give me both of them raw answers" 'origin:{kind:"peer"},promptSource:"system",entrypoint:"cli"'
    u "2026-09-17T10:04:30Z" $'relay\tline\nnext: give me both of them raw answers' 'entrypoint:"cli"'
    u "2026-09-17T10:05:00Z" $'<task-notification>\n<summary>give me both of them raw answers</summary>' 'origin:{kind:"task-notification"}'
    u "2026-09-17T10:05:30Z" "This session is being continued. give me both of them raw answers" "${HUMAN}"
    u "2026-09-17T10:06:00Z" "meta: give me both of them raw answers" "isMeta:true,${HUMAN}"
    u "2026-09-17T10:06:30Z" "side: give me both of them raw answers" "isSidechain:true,${HUMAN}"
    jq -nc '{type:"assistant",timestamp:"2026-09-17T10:07:00Z",message:{role:"assistant",content:"give me both of them raw answers"}}'
    jq -nc '{type:"attachment",timestamp:"2026-09-17T10:08:00Z",attachment:{type:"queued_command",commandMode:"prompt",prompt:"the supermodel panelist spoke",origin:{kind:"human"}}}'
    jq -nc '{type:"attachment",timestamp:"2026-09-17T10:08:30Z",attachment:{type:"queued_command",commandMode:"task-notification",prompt:"queued note: give me both of them raw answers"}}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:09:00Z",origin:{kind:"human"},message:{role:"user",content:("note" + ([0] | implode) + " put the model panels to work")}}'
    u "2026-09-17T10:09:10Z" "same words from two places" 'entrypoint:"cli"'
    u "2026-09-17T10:09:20Z" "same words from two places" "${HUMAN}"
    jq -nc '{type:"attachment",timestamp:"2026-09-17T10:09:25Z",attachment:{type:"queued_command",commandMode:"prompt",prompt:"queued without origin"}}'
    jq -nc '{type:"attachment",timestamp:"2026-09-17T10:09:26Z",attachment:{type:"queued_command",commandMode:"prompt",isMeta:true,prompt:"queued meta: give me both of them raw answers",origin:{kind:"human"}}}'
    u "2026-09-17T10:09:27Z" "text from a script and a relay" 'promptSource:"sdk",entrypoint:"sdk-py"'
    u "2026-09-17T10:09:29Z" "text from a teammate and a script" 'origin:{kind:"peer"},entrypoint:"cli"'
    u "2026-09-17T10:09:29Z" "text from a teammate and a script" 'promptSource:"sdk",entrypoint:"sdk-py"'
    u "2026-09-17T10:09:31Z" "Base directory for this skill: /x/cache/acsm/auto-claude-skills/3.89.3/skills/panel" 'entrypoint:"cli"' 
    u "2026-09-17T10:09:28Z" "text from a script and a relay" 'entrypoint:"cli"'
    u "2026-09-17T10:09:30Z" "a supermodel panelist and a model panel" "${HUMAN}"
    u "2026-09-17T10:09:40Z" "x.model panelist and supermodel panel.x" "${HUMAN}"
    printf '%s\n' 'this line is not json'
} > "${PROJ}/p1/s1.jsonl"
u "2026-09-17T10:10:00Z" "subagent brief: give me both of them raw answers" "${HUMAN}" > "${PROJ}/p1/s1/subagents/agent-x.jsonl"
{
    u "2026-08-01T10:00:00Z" "an old prompt about nothing" "${HUMAN}"
    u "2026-09-01T23:00:00Z" "a prompt on the boundary day" "${HUMAN}"
} > "${PROJ}/p2/s2.jsonl"
u "2026-09-17T10:11:00Z" "see the model panel" "${HUMAN}" > "${PROJ}/${USPROJ}/s3.jsonl"

OUT="${TEST_TMPDIR}/out"
mkdir -p "${OUT}"

# E1: extraction keeps prompts once each, labelled by provenance.
EX_LOG="$(python3 "${EXTRACT}" --projects "${PROJ}" --out "${OUT}/prompts.jsonl" 2>&1)"
assert_equals "E1: extraction succeeds" "0" "$?"
has_line "E1: 17 distinct prompts" "prompts 17" "${EX_LOG}"
has_line "E1: 11 labelled human (typed, queued, from any project)" "source human: 11" "${EX_LOG}"
has_line "E1: the peer messages are labelled peer" "source peer: 2" "${EX_LOG}"
has_line "E1: the pipeline prompt is labelled sdk" "source sdk: 1" "${EX_LOG}"
has_line "E1: the prompts without provenance are unlabelled, not human" "source unlabelled: 3" "${EX_LOG}"
assert_equals "E1: the file matches the count" "17" "$(wc -l < "${OUT}/prompts.jsonl" | tr -d ' ')"
assert_equals "E1: a prompt seen from sdk then a person keeps the human label" "human" \
    "$(source_of_prompt "${OUT}/prompts.jsonl" "ask codex and gemini")"
assert_equals "E1: the queued prompt is read, labelled human" "human" \
    "$(source_of_prompt "${OUT}/prompts.jsonl" "the supermodel")"
assert_equals "E1: an unlabelled cli prompt is not assumed human" "unlabelled" \
    "$(source_of_prompt "${OUT}/prompts.jsonl" "relay")"
assert_equals "E1: a prompt seen from a teammate then from a script keeps the teammate label" "peer" \
    "$(source_of_prompt "${OUT}/prompts.jsonl" "text from a teammate")"
assert_equals "E1: a prompt seen unlabelled then from a person is labelled human" "human" \
    "$(source_of_prompt "${OUT}/prompts.jsonl" "same words")"
assert_equals "E1: a prompt seen from sdk then without provenance is labelled unlabelled" "unlabelled" \
    "$(source_of_prompt "${OUT}/prompts.jsonl" "text from a script")"
assert_equals "E1: a queued prompt without origin is read, unlabelled" "unlabelled" \
    "$(source_of_prompt "${OUT}/prompts.jsonl" "queued without origin")"
assert_equals "E1: surrounding whitespace is stripped" "1" \
    "$(jq -r 'select(.prompt == "ASK A FEW OF THEM SEPARATELY AND GIVE ME THE RAW ANSWERS") | .source' "${OUT}/prompts.jsonl" | wc -l | tr -d ' ')"
for _gone in "subagent brief" "tool output" "task-notification" "queued note" "queued meta" "This session" "meta:" "side:" "Base directory"; do
    assert_equals "E1: not kept: ${_gone}" "0" "$(grep -cF "${_gone}" "${OUT}/prompts.jsonl")"
done

# E3: an existing output file is replaced: truncated and made private.
for _i in $(seq 1 2000); do printf 'stale\n'; done > "${OUT}/reuse.jsonl"
chmod 644 "${OUT}/reuse.jsonl"
python3 "${EXTRACT}" --projects "${PROJ}" --out "${OUT}/reuse.jsonl" >/dev/null 2>&1
assert_equals "E3: a reused output holds only this run's records" "17" "$(wc -l < "${OUT}/reuse.jsonl" | tr -d ' ')"
assert_equals "E3: ... and no stale line" "0" "$(grep -c '^stale$' "${OUT}/reuse.jsonl")"
assert_equals "E3: ... and is mode 0600" "0o600" "$(mode_of "${OUT}/reuse.jsonl")"
assert_equals "E3: a new output is mode 0600" "0o600" "$(mode_of "${OUT}/prompts.jsonl")"

# E2: --since filters by the prompt's date and rejects a bad date without writing.
EX2="$(python3 "${EXTRACT}" --projects "${PROJ}" --since 2026-09-01 --out "${OUT}/since.jsonl" 2>&1)"
has_line "E2: --since drops the older prompt and keeps the boundary day" "prompts 16" "${EX2}"
python3 "${EXTRACT}" --projects "${PROJ}" --since 2026-13-45 --out "${OUT}/bad-since.jsonl" >/dev/null 2>&1
assert_equals "E2: a malformed --since exits 2" "2" "$?"
no_file "E2: ... and writes nothing" "${OUT}/bad-since.jsonl"
for _bad in 20260901 2026-W36-1 2026-9-1; do
    python3 "${EXTRACT}" --projects "${PROJ}" --since "${_bad}" --out "${OUT}/bad-since.jsonl" >/dev/null 2>&1
    assert_equals "E2: a non-canonical --since (${_bad}) exits 2" "2" "$?"
done

# G: no script writes prompt text inside any git work tree.
OTHER="${TEST_TMPDIR}/other-repo"
git init -q "${OTHER}"
ln -s "${PROBE}" "${TEST_TMPDIR}/probe-link"
UPPER="$(printf '%s' "${PROBE}" | tr '[:lower:]' '[:upper:]')"
guard_case() { # <label> <out-file> <path that must not appear>
    python3 "${EXTRACT}" --projects "${PROJ}" --out "$2" >/dev/null 2>&1
    assert_equals "G: extract refuses $1" "2" "$?"
    python3 "${ROUTED}" --skill panel --projects "${PROJ}" --out "$2" >/dev/null 2>&1
    assert_equals "G: routed refuses $1" "2" "$?"
    no_file "G: nothing written for $1" "$3"
}
guard_case "a path in this repository" "${PROBE}/leak.jsonl" "${PROBE}/leak.jsonl"
REPO_MSG="refusing to write prompt text inside a git repository"
_err="$(python3 "${EXTRACT}" --projects "${PROJ}" --out "${OTHER}/.git/leak.jsonl" 2>&1 >/dev/null)"
assert_contains "G: extract names the repository it found (not a cannot-check refusal)" "${REPO_MSG}" "${_err}"
_err="$(python3 "${ROUTED}" --skill panel --projects "${PROJ}" --out "${PROBE}/leak.jsonl" 2>&1 >/dev/null)"
assert_contains "G: routed names the repository it found" "${REPO_MSG}" "${_err}"
guard_case "a not-yet-existing directory in this repository" "${PROBE}/nope/leak.jsonl" "${PROBE}/nope"
guard_case "a symlinked parent into this repository" "${TEST_TMPDIR}/probe-link/leak.jsonl" "${PROBE}/leak.jsonl"
guard_case "another git work tree" "${OTHER}/leak.jsonl" "${OTHER}/leak.jsonl"
ln -s "${PROBE}/dangle.jsonl" "${TEST_TMPDIR}/dangle.jsonl"
guard_case "a dangling symlink into this repository" "${TEST_TMPDIR}/dangle.jsonl" "${PROBE}/dangle.jsonl"
ln -s "${OTHER}/dangle.jsonl" "${TEST_TMPDIR}/dangle-other.jsonl"
guard_case "a dangling symlink into another git work tree" "${TEST_TMPDIR}/dangle-other.jsonl" "${OTHER}/dangle.jsonl"
guard_case "a repository's .git directory" "${OTHER}/.git/leak.jsonl" "${OTHER}/.git/leak.jsonl"
guard_case "'..' after a symlink into this repository" "${TEST_TMPDIR}/probe-link/../leak.jsonl" \
    "${PROJECT_ROOT}/tests/probes/leak.jsonl"
mkdir -p "${OTHER}/stale"
printf '%s\n' "gitdir: ${TEST_TMPDIR}/gone/.git" > "${OTHER}/stale/.git"
guard_case "a directory whose broken .git file hides the enclosing repository" \
    "${OTHER}/stale/leak.jsonl" "${OTHER}/stale/leak.jsonl"

GIT_CEILING_DIRECTORIES="$(dirname "${PROBE}")" \
    guard_case "a path in this repository with git discovery disabled by the environment" \
    "${PROBE}/leak.jsonl" "${PROBE}/leak.jsonl"
: > "${OTHER}/tracked.txt"
ln "${OTHER}/tracked.txt" "${TEST_TMPDIR}/hardlink.jsonl"
guard_case "a hard link to a file in another repository" "${TEST_TMPDIR}/hardlink.jsonl" "${TEST_TMPDIR}/never"
chmod 644 "${OTHER}/tracked.txt"
guard_case "a hard link, checked before any change to the file" "${TEST_TMPDIR}/hardlink.jsonl" "${TEST_TMPDIR}/never"
assert_equals "G: the hard-linked file is untouched" "0" "$(wc -c < "${OTHER}/tracked.txt" | tr -d ' ')"
assert_equals "G: ... and keeps its permissions" "0o644" "$(mode_of "${OTHER}/tracked.txt")"
: > "${TEST_TMPDIR}/plain-target"
ln -s "${TEST_TMPDIR}/plain-target" "${TEST_TMPDIR}/symlink-out.jsonl"
guard_case "a symlink as the output file, even outside a repository" "${TEST_TMPDIR}/symlink-out.jsonl" "${TEST_TMPDIR}/never"
assert_equals "G: the symlink target is untouched" "0" "$(wc -c < "${TEST_TMPDIR}/plain-target" | tr -d ' ')"
mkfifo "${TEST_TMPDIR}/fifo.jsonl"
fifo_case() { # <label> <command...>: the command must exit 2 within 10 seconds
    local _label="$1"; shift
    "$@" >/dev/null 2>&1 &
    local _pid=$! _n=0
    while kill -0 "${_pid}" 2>/dev/null && [ "${_n}" -lt 100 ]; do
        sleep 0.1
        _n=$((_n + 1))
    done
    if kill -0 "${_pid}" 2>/dev/null; then
        kill -9 "${_pid}" 2>/dev/null
        _record_fail "${_label}" "still running after 10s (a FIFO must not block the open)"
        return
    fi
    wait "${_pid}"
    assert_equals "${_label}" "2" "$?"
}
fifo_case "G: extract refuses a FIFO as the output file, without blocking" \
    python3 "${EXTRACT}" --projects "${PROJ}" --out "${TEST_TMPDIR}/fifo.jsonl"
fifo_case "G: routed refuses a FIFO as the output file, without blocking" \
    python3 "${ROUTED}" --skill panel --projects "${PROJ}" --out "${TEST_TMPDIR}/fifo.jsonl"
mkfifo "${TEST_TMPDIR}/fifo-read.jsonl"
cat "${TEST_TMPDIR}/fifo-read.jsonl" > "${TEST_TMPDIR}/fifo-drain" &
FIFO_READER=$!
fifo_case "G: extract refuses a FIFO even when it opens (someone is reading it)" \
    python3 "${EXTRACT}" --projects "${PROJ}" --out "${TEST_TMPDIR}/fifo-read.jsonl"
assert_equals "G: ... and wrote nothing into it" "0" "$(wc -c < "${TEST_TMPDIR}/fifo-drain" | tr -d ' ')"
kill "${FIFO_READER}" 2>/dev/null
wait "${FIFO_READER}" 2>/dev/null
# Without git, nothing can be checked, so every script refuses, even outside any repository.
NOGIT="${TEST_TMPDIR}/nogit-bin"
mkdir -p "${NOGIT}"
for _tool in jq tr dirname env; do
    ln -s "$(command -v "${_tool}")" "${NOGIT}/${_tool}"
done
PY="$(command -v python3)"
for _script in "${EXTRACT}" "${ROUTED}"; do
    _err="$(PATH="${NOGIT}" "${PY}" "${_script}" --skill panel --projects "${PROJ}" --out "${OUT}/nogit.jsonl" 2>&1 >/dev/null)"
    [ "${_script}" = "${EXTRACT}" ] && _err="$(PATH="${NOGIT}" "${PY}" "${_script}" --projects "${PROJ}" --out "${OUT}/nogit.jsonl" 2>&1 >/dev/null)"
    assert_contains "G: without git, ${_script##*/} refuses because it cannot check" "git is unavailable" "${_err}"
    no_file "G: without git, ${_script##*/} writes nothing" "${OUT}/nogit.jsonl"
done
_err="$(PATH="${NOGIT}" /bin/bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/nogit" < /dev/null 2>&1 >/dev/null)"
assert_contains "G: without git, replay refuses because it cannot check" "git is unavailable" "${_err}"
no_file "G: without git, replay creates nothing" "${OUT}/nogit"
# A git that fails for any reason other than "not a git repository" is not an answer either.
FAKEGIT="${TEST_TMPDIR}/fakegit-bin"
mkdir -p "${FAKEGIT}"
printf '%s\n' '#!/bin/sh' 'echo "fatal: detected dubious ownership in repository" >&2' 'exit 128' > "${FAKEGIT}/git"
chmod +x "${FAKEGIT}/git"
_err="$(PATH="${FAKEGIT}:${PATH}" python3 "${EXTRACT}" --projects "${PROJ}" --out "${OUT}/fakegit.jsonl" 2>&1 >/dev/null)"
assert_contains "G: extract refuses when git cannot tell" "git could not tell" "${_err}"
_err="$(PATH="${FAKEGIT}:${PATH}" python3 "${ROUTED}" --skill panel --projects "${PROJ}" --out "${OUT}/fakegit.jsonl" 2>&1 >/dev/null)"
assert_contains "G: routed refuses when git cannot tell" "git could not tell" "${_err}"
no_file "G: ... and neither writes" "${OUT}/fakegit.jsonl"
_err="$(PATH="${FAKEGIT}:${PATH}" bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/fakegit" < /dev/null 2>&1 >/dev/null)"
assert_contains "G: replay refuses when git cannot tell" "git could not tell" "${_err}"
no_file "G: ... and creates nothing" "${OUT}/fakegit"
# Only git's own no-repository message counts, not those words inside a path it prints:
# that is a different failure (a broken .git file), and git stopped searching early.
DECOY="${TEST_TMPDIR}/decoy-bin"
mkdir -p "${DECOY}"
printf '%s\n' '#!/bin/sh' \
    'echo "fatal: not a git repository: \x27/x/fatal: not a git repository (or any of the parent directories)\x27" >&2' \
    'exit 128' > "${DECOY}/git"
chmod +x "${DECOY}/git"
_err="$(PATH="${DECOY}:${PATH}" python3 "${EXTRACT}" --projects "${PROJ}" --out "${OUT}/decoy.jsonl" 2>&1 >/dev/null)"
assert_contains "G: extract refuses when the no-repository words are only inside a path" "git could not tell" "${_err}"
no_file "G: ... and writes nothing" "${OUT}/decoy.jsonl"
_err="$(PATH="${DECOY}:${PATH}" python3 "${ROUTED}" --skill panel --projects "${PROJ}" --out "${OUT}/decoy.jsonl" 2>&1 >/dev/null)"
assert_contains "G: routed refuses the same" "git could not tell" "${_err}"
_err="$(PATH="${DECOY}:${PATH}" bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/decoy" < /dev/null 2>&1 >/dev/null)"
assert_contains "G: replay refuses the same" "git could not tell" "${_err}"
no_file "G: ... and creates nothing" "${OUT}/decoy"
# Git stops at a mount point unless told otherwise; that is not an answer about the parents
# above it, so the scripts retry across filesystems and use only the full-search answer.
BOUNDARY="${TEST_TMPDIR}/boundary-bin"
mkdir -p "${BOUNDARY}"
printf '%s\n' '#!/bin/sh' \
    'if [ -n "${GIT_DISCOVERY_ACROSS_FILESYSTEM}" ]; then' \
    '  echo "fatal: not a git repository (or any of the parent directories): .git" >&2' \
    'else' \
    '  echo "fatal: not a git repository (or any parent up to mount point /tmp)" >&2' \
    '  echo "Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set)." >&2' \
    'fi' \
    'exit 128' > "${BOUNDARY}/git"
chmod +x "${BOUNDARY}/git"
PATH="${BOUNDARY}:${PATH}" python3 "${EXTRACT}" --projects "${PROJ}" --out "${OUT}/boundary.jsonl" >/dev/null 2>&1
assert_equals "G: extract retries across a filesystem boundary and writes when there is no repository" "0" "$?"
PATH="${BOUNDARY}:${PATH}" bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/boundary" < /dev/null >/dev/null 2>&1
assert_equals "G: replay does the same" "0" "$?"
printf '%s\n' '#!/bin/sh' \
    'if [ -n "${GIT_DISCOVERY_ACROSS_FILESYSTEM}" ]; then' \
    '  echo "/x/.git"; exit 0' \
    'fi' \
    'echo "fatal: not a git repository (or any parent up to mount point /tmp)" >&2' \
    'exit 128' > "${BOUNDARY}/git"
_err="$(PATH="${BOUNDARY}:${PATH}" python3 "${EXTRACT}" --projects "${PROJ}" --out "${OUT}/boundary2.jsonl" 2>&1 >/dev/null)"
assert_contains "G: a repository found above the mount point still refuses" "inside a git repository" "${_err}"
no_file "G: ... and writes nothing" "${OUT}/boundary2.jsonl"
_err="$(PATH="${BOUNDARY}:${PATH}" bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/boundary2" < /dev/null 2>&1 >/dev/null)"
assert_contains "G: replay refuses the same" "inside a git repository" "${_err}"
no_file "G: ... and creates nothing" "${OUT}/boundary2"
if [ -d "${UPPER}" ]; then
    guard_case "a case-changed path on a case-insensitive volume" "${UPPER}/leak.jsonl" "${PROBE}/leak.jsonl"
fi
_err="$(bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${PROBE}/leak" < /dev/null 2>&1 >/dev/null)"
assert_equals "G: replay refuses a directory in this repository" "2" "$?"
assert_contains "G: ... naming the repository it found (not a cannot-check refusal)" "${REPO_MSG}" "${_err}"
no_file "G: ... and creates nothing" "${PROBE}/leak"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${PROBE}/nope/deeper" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses a not-yet-existing directory in this repository" "2" "$?"
no_file "G: ... and creates nothing" "${PROBE}/nope"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${TEST_TMPDIR}/probe-link" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses a symlink into this repository as the directory" "2" "$?"
no_file "G: ... and writes nothing" "${PROBE}/matches.tsv"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OTHER}/replay" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses another git work tree" "2" "$?"
no_file "G: ... and creates nothing" "${OTHER}/replay"
mkdir -p "${OUT}/lnk"
: > "${TEST_TMPDIR}/lnk-target"
ln -s "${TEST_TMPDIR}/lnk-target" "${OUT}/lnk/matches.tsv"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/lnk" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses to write matches.tsv through a symlink" "2" "$?"
mkdir -p "${OUT}/hl"
ln "${OTHER}/tracked.txt" "${OUT}/hl/matches.tsv"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/hl" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses to write matches.tsv through a hard link" "2" "$?"
assert_equals "G: ... and the linked file is untouched" "0" "$(wc -c < "${OTHER}/tracked.txt" | tr -d ' ')"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${TEST_TMPDIR}/newdir/../probe-link/leak" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses a '..' path" "2" "$?"
no_file "G: ... and creates nothing in the repository" "${PROBE}/leak"
no_file "G: ... or on the way" "${TEST_TMPDIR}/newdir"
GIT_CEILING_DIRECTORIES="$(dirname "${PROBE}")" \
    bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${PROBE}/leak" < /dev/null >/dev/null 2>&1
assert_equals "G: replay ignores git discovery settings from the environment" "2" "$?"
no_file "G: ... and creates nothing" "${PROBE}/leak"
_err="$(bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OTHER}/.git/replay" < /dev/null 2>&1 >/dev/null)"
assert_contains "G: replay names the repository for a .git directory" "${REPO_MSG}" "${_err}"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OTHER}/.git/replay" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses a repository's .git directory" "2" "$?"
no_file "G: ... and creates nothing" "${OTHER}/.git/replay"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OTHER}/stale/replay" < /dev/null >/dev/null 2>&1
assert_equals "G: replay refuses a directory whose broken .git file hides the repository" "2" "$?"
no_file "G: ... and creates nothing" "${OTHER}/stale/replay"
if [ -d "${UPPER}" ]; then
    bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${UPPER}/leak" < /dev/null >/dev/null 2>&1
    assert_equals "G: replay refuses a case-changed path" "2" "$?"
    no_file "G: ... and creates nothing" "${PROBE}/leak"
fi
env -u PYTHONDONTWRITEBYTECODE python3 "${ROUTED}" --skill panel --projects "${PROJ}" --out "${OUT}/pyc.jsonl" >/dev/null 2>&1
no_file "G: routed.py leaves no bytecode cache in the repository" "${PROBE}/__pycache__"

# R1: replay matches like the hook.
RP_LOG="$(bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/replay" < /dev/null 2>&1)"
assert_equals "R1: replay succeeds" "0" "$?"
has_line "R1: every record is read once (NUL and US do not split records)" "prompts 17" "${RP_LOG}"
has_line "R1: sources are counted" "source human: 11" "${RP_LOG}"
has_line "R1: ... including the labelled non-human ones" "source peer: 2" "${RP_LOG}"
has_line "R1: trigger 0 keeps scanning past an in-word hit, and discards prompts with only in-word hits ('.' counts as a word character)" \
    "trigger 0: 3 (human 3, in-word discarded 2)" "${RP_LOG}"
has_line "R1: trigger 1 counts the named-model prompt" "trigger 1: 1 (human 1, in-word discarded 0)" "${RP_LOG}"
has_line "R1: trigger 5 counts the upper-case prompt after lowercasing, and the non-human ones" \
    "trigger 5: 3 (human 1, in-word discarded 0)" "${RP_LOG}"
has_line "R1: a prompt counts for every trigger it hits, not only the first" \
    "trigger 6: 1 (human 1, in-word discarded 0)" "${RP_LOG}"
has_line "R1: matched prompts, with the human share" "matched prompts: 7 (human 5)" "${RP_LOG}"
M="${OUT}/replay/matches.tsv"
assert_equals "R1: matches.tsv is mode 0600" "0o600" "$(mode_of "${M}")"
chmod 644 "${M}"
printf 'stale\n' >> "${M}"
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/replay" < /dev/null >/dev/null 2>&1
assert_equals "R1: a second run into the same directory succeeds" "0" "$?"
assert_equals "R1: ... replaces matches.tsv (no stale line)" "0" "$(grep -c '^stale$' "${M}")"
assert_equals "R1: ... and makes it private again" "0o600" "$(mode_of "${M}")"
assert_equals "R1: matches.tsv has one line per matched prompt" "7" "$(wc -l < "${M}" | tr -d ' ')"
assert_equals "R1: every line has exactly 5 fields (tabs and newlines flattened)" "0" \
    "$(awk -F'\t' 'NF != 5' "${M}" | wc -l | tr -d ' ')"
assert_equals "R1: the multi-trigger prompt lists every index" "1" "$(grep -c $'^1,6\thuman\t' "${M}")"
assert_equals "R1: the US-named project stays in its own column" "1" \
    "$(awk -F'\t' '$2 == "human" && $4 == "p us" && $5 == "see the model panel"' "${M}" | wc -l | tr -d ' ')"
assert_equals "R1: the unrelated prompt is not listed" "0" "$(grep -c 'login bug' "${M}")"
assert_equals "R1: the in-word-only prompts are not listed" "0" "$(grep -c -e 'panelist spoke' -e 'x.model' "${M}")"
assert_equals "R1: a boundary hit after an in-word hit is listed" "1" "$(grep -c 'a supermodel panelist and a model panel' "${M}")"

# R2: bad inputs are errors, not empty results.
bash "${REPLAY}" no-such-skill "${OUT}/prompts.jsonl" "${OUT}/replay2" < /dev/null >/dev/null 2>&1
assert_equals "R2: an unknown skill exits 2" "2" "$?"
{ head -2 "${OUT}/prompts.jsonl"; printf '%s\n' '{"prompt": ' ; } > "${OUT}/truncated.jsonl"
bash "${REPLAY}" panel "${OUT}/truncated.jsonl" "${OUT}/replay3" < /dev/null >/dev/null 2>&1
assert_equals "R2: a truncated prompts file exits 2" "2" "$?"
printf '%s\n' '{"prompt": null}' > "${OUT}/nullprompt.jsonl"
bash "${REPLAY}" panel "${OUT}/nullprompt.jsonl" "${OUT}/replay4" < /dev/null >/dev/null 2>&1
assert_equals "R2: a record without a string prompt exits 2" "2" "$?"

# L1: live routings, paired through parentUuid.
LIVE="${TEST_TMPDIR}/live"
mkdir -p "${LIVE}/p3"
PANEL_LINE="Domain: panel -> Skill(auto-claude-skills:panel)"
ctx() { # <uuid> <parent> <ts> <hookEvent> <content>
    jq -nc --arg u "$1" --arg p "$2" --arg t "$3" --arg e "$4" --arg c "$5" \
        '{type:"attachment",uuid:$u,parentUuid:$p,timestamp:$t,attachment:{type:"hook_additional_context",hookEvent:$e,hookName:($e + ":x"),content:[$c]}}'
}
uu() { # <uuid> <parent> <ts> <content> <extra>
    jq -nc --arg u "$1" --arg p "$2" --arg t "$3" --arg c "$4" \
        "{type:\"user\",uuid:\$u,parentUuid:(if \$p == \"\" then null else \$p end),timestamp:\$t,message:{role:\"user\",content:\$c},$5}"
}
ACT="SKILL ACTIVATION (1 skills | IMPLEMENT)"
{
    uu u1 "" "2026-09-18T09:00:00Z" "ask a few of them separately and give me the raw answers" "${HUMAN}"
    ctx a1 u1 "2026-09-18T09:00:01Z" UserPromptSubmit "${ACT}"$'\n'"${PANEL_LINE}"
    ctx a1b u1 "2026-09-18T09:00:01Z" UserPromptSubmit "${ACT}"$'\n'"${PANEL_LINE}"
    uu u2 a1b "2026-09-18T09:05:00Z" $'<task-notification>\n<summary>done</summary>' 'origin:{kind:"task-notification"}'
    ctx a2 u2 "2026-09-18T09:05:01Z" UserPromptSubmit "${ACT}"$'\n'"${PANEL_LINE}"
    uu u4 a2 "2026-09-18T09:06:00Z" "earlier prompt" "${HUMAN}"
    jq -nc '{type:"assistant",uuid:"x4",parentUuid:"u4",timestamp:"2026-09-18T09:06:10Z",message:{role:"assistant",content:"ok"}}'
    jq -nc '{type:"attachment",uuid:"q5",parentUuid:"x4",timestamp:"2026-09-18T09:07:00Z",attachment:{type:"queued_command",commandMode:"task-notification",prompt:"<task-notification>done</task-notification>"}}'
    ctx a5 q5 "2026-09-18T09:07:01Z" UserPromptSubmit "${ACT}"$'\n'"${PANEL_LINE}"
    uu u6 a5 "2026-09-18T09:10:00Z" "fix the login bug" "${HUMAN}"
    ctx a6 u6 "2026-09-18T09:10:01Z" UserPromptSubmit "${ACT}"$'\n'"Process: systematic-debugging -> Skill(superpowers:systematic-debugging)"
    ctx a6b u6 "2026-09-18T09:10:02Z" PostToolUse "${ACT}"$'\n'"${PANEL_LINE}"
    uu u7 a6 "2026-09-18T09:11:00Z" "unrelated prompt" "${HUMAN}"
    ctx a7 u7 "2026-09-18T09:11:01Z" UserPromptSubmit "${ACT}"$'\n'"Domain: sub-panel -> Skill(auto-claude-skills:sub-panel)"$'\n'"Domain: sub-panel -> Skill(auto-claude-skills:panel)"$'\n'"Domain: panel -> Skill(other-plugin:panel)"$'\n'"see Skill(auto-claude-skills:panel)"
    ctx a7b u7 "2026-09-18T09:11:02Z" UserPromptSubmit "${PANEL_LINE}"
    uu m1 "" "2026-09-18T09:11:30Z" "Base directory for this skill: /x/cache/acsm/auto-claude-skills/3.87.1/skills/panel" "isMeta:true"
    uu m2 "" "2026-09-20T09:00:00Z" "Base directory for this skill: /x/cache/acsm/auto-claude-skills/3.89.3/skills/panel" "isMeta:true"
    uu m3 "" "2026-09-19T09:00:00Z" "Base directory for this skill: /x/cache/acsm/auto-claude-skills/3.89.3/skills/panel" "isMeta:true"
    ctx s1 "" "2026-09-21T08:00:00Z" SessionStart "Preset active: spec-driven (/x/cache/acsm/auto-claude-skills/3.89.4/config/presets/spec-driven.json)"
    ctx s2 "" "2026-09-21T08:00:00Z" PostToolUse "see /x/cache/acsm/auto-claude-skills/9.9.8/skills/panel"
    uu q15 "" "2026-09-21T08:05:00Z" "Base directory for this skill: /x/cache/acsm/auto-claude-skills/9.9.7/skills/panel" "${HUMAN}"
    uu q16 "" "2026-09-21T08:06:00Z" "note: /x/cache/acsm/auto-claude-skills/9.9.6/skills/panel" "isMeta:true"
    jq -nc '{type:"assistant",uuid:"q17",timestamp:"2026-09-21T08:07:00Z",isMeta:true,message:{role:"assistant",content:"Base directory for this skill: /x/cache/acsm/auto-claude-skills/9.9.5/skills/panel"}}'
    uu u10 a7 "2026-09-18T09:12:00Z" "prompt ten" "${HUMAN}"
    uu u11 u10 "2026-09-18T09:12:30Z" "prompt eleven" "${HUMAN}"
    ctx a10 u10 "2026-09-18T09:12:31Z" UserPromptSubmit "${ACT}"$'\n'"${PANEL_LINE}"
    uu u13 a10 "2026-09-18T09:12:40Z" "prompt thirteen" "${HUMAN}"
    jq -nc '{type:"assistant",uuid:"x13",parentUuid:"u13",timestamp:"2026-09-18T09:12:41Z",message:{role:"assistant",content:"ok"}}'
    jq -nc '{type:"attachment",uuid:"y13",parentUuid:"x13",timestamp:"2026-09-18T09:12:42Z",attachment:{type:"hook_additional_context",hookEvent:"PostToolUse",content:["x"]}}'
    ctx a13 y13 "2026-09-18T09:12:43Z" UserPromptSubmit "${ACT}"$'\n'"${PANEL_LINE}"
    printf '%s\n' '[1, 2]' '"just a string"' 'null'
    uu q14 "" "2026-09-18T09:14:00Z" "look at /x/cache/acsm/auto-claude-skills/9.9.9/skills/panel" "${HUMAN}"
    uu u12 "" "2026-08-01T09:00:00Z" "old prompt" "${HUMAN}"
    ctx a12 u12 "2026-09-18T09:13:00Z" UserPromptSubmit "${ACT}"$'\n'"${PANEL_LINE}"
} > "${LIVE}/p3/s3.jsonl"
LV_LOG="$(python3 "${ROUTED}" --skill panel --projects "${LIVE}" --since 2026-09-01 --out "${OUT}/routed.jsonl" 2>&1)"
assert_equals "L1: live scan succeeds" "0" "$?"
has_line "L1: one routing per prompt, UserPromptSubmit only, this plugin's skill only, --since on the prompt date" \
    "routings 5" "${LV_LOG}"
has_line "L1: three human prompts, one reached through several non-input entries" "source human: 3" "${LV_LOG}"
has_line "L1: two notifications, the queued one included" "source not-a-prompt:task-notification: 2" "${LV_LOG}"
has_line "L1: each plugin version's first and last date" "plugin auto-claude-skills 3.87.1: 2026-09-18 .. 2026-09-18" "${LV_LOG}"
has_line "L1: ... across out-of-order entries" "plugin auto-claude-skills 3.89.3: 2026-09-19 .. 2026-09-20" "${LV_LOG}"
has_line "L1: the SessionStart hook output is install evidence" "plugin auto-claude-skills 3.89.4: 2026-09-21 .. 2026-09-21" "${LV_LOG}"
assert_equals "L1: a version path quoted in a prompt or other context is not evidence of an install" "0" \
    "$(printf '%s\n' "${LV_LOG}" | grep -c -e '9\.9\.9' -e '9\.9\.8' -e '9\.9\.7' -e '9\.9\.6' -e '9\.9\.5')"
assert_equals "L1: the multi-hop prompt is listed" "1" "$(grep -c '"prompt thirteen"' "${OUT}/routed.jsonl")"
assert_equals "L1: the prompt a routing answered is listed (parentUuid, not file order)" "1" \
    "$(grep -c '"prompt ten"' "${OUT}/routed.jsonl")"
assert_equals "L1: the prompt after it is not" "0" "$(grep -c 'prompt eleven' "${OUT}/routed.jsonl")"
assert_equals "L1: the walk stops at a queued notification" "0" "$(grep -c 'earlier prompt' "${OUT}/routed.jsonl")"
assert_equals "L1: other skills and PostToolUse context are not listed" "0" "$(grep -c 'login bug' "${OUT}/routed.jsonl")"
assert_equals "L1: name and plugin collisions, and context without a routing block, are not listed" "0" "$(grep -c 'unrelated prompt' "${OUT}/routed.jsonl")"
LV_ALL="$(python3 "${ROUTED}" --skill panel --projects "${LIVE}" --out "${OUT}/routed-all.jsonl" 2>&1)"
has_line "L1: without --since the old prompt is counted" "routings 6" "${LV_ALL}"

# L2: the routed output feeds replay.
RR_LOG="$(bash "${REPLAY}" panel "${OUT}/routed.jsonl" "${OUT}/replay-routed" < /dev/null 2>&1)"
assert_equals "L2: replay reads routed.py output" "0" "$?"
has_line "L2: all routed records are replayed" "prompts 5" "${RR_LOG}"
has_line "L2: the notification source is kept" "source not-a-prompt:task-notification: 2" "${RR_LOG}"
has_line "L2: the consultation prompt is attributed to trigger 5" "trigger 5: 1 (human 1, in-word discarded 0)" "${RR_LOG}"

teardown_test_env
print_summary
