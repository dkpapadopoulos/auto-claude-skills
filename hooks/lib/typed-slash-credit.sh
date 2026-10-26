#!/usr/bin/env bash
# typed-slash-credit.sh — a TYPED slash command naming an installed, credited
# REVIEW skill earns the same evidence as a Skill tool return (openspec change
# review-credit-from-evidence, design decision 1).
#
# Measured on Claude Code 2.1.308: a typed skill reaches UserPromptSubmit as the
# raw "/name args" and fires no Skill tool hook, so nothing recorded it. The
# routing hook's slash early exit calls typed_slash_credit, which pipes a
# synthetic PostToolUse(Skill) payload (acs_source "typed-slash") to the REAL
# completion hook, so every evidence write is that hook's own. Never a copy.
#
# Credit is NARROW by construction, and every failure narrows it further:
#   - the prompt kind must be exactly "prompt" (not a task notification, a
#     peer/cross-session message, or an unclassifiable prompt);
#   - only the FIRST token, after optional leading whitespace, is read;
#   - the name must be a credited REVIEW name (credited-skills.sh). A typed
#     verification-before-completion is never credited: VERIFY status is #301's
#     live shadow population. credited-skills.sh unreadable => no typed credit;
#   - the name must exist: a bare built-in (code-review, security-review) on a
#     Claude Code >= 2.1.308 (AI_AGENT; an unknown slash command reaches this
#     hook exactly like a real one, so the version is the built-in's only
#     witness), or an available entry in the session's skill registry. A typed
#     missing name must not be cheaper than a Skill call to it, which errors and
#     credits nothing. Without acs_cc_version the built-in branch fails closed.
#
# Fork budget (preflight F5): nothing here runs on a prompt that does not start
# with `/` (the caller's own regex gates it), and nothing forks until a credited
# name has been recognised in pure bash. A slash prompt costs the caller's one
# subshell; a credited one then a version capture (built-in names only), at
# most two jq (registry check, payload) and
# the completion hook, run synchronously, so its latency is the prompt's.
#
# The rule is the FIRST token: a prompt the person begins with a typed credited
# command credits even when other text (a pasted notification, a peer message)
# follows it; the same command anywhere after the first token never does.
#
# Sourced by skill-activation-hook.sh only (bash, `set -uo pipefail`, no ERR
# trap), INSIDE a subshell with stdout/stderr silenced: a function cannot
# contain an `exit` or a `set -u` abort at load, a subshell can, so a broken
# lib costs only the typed credit and routing stays exit 0 with no output. The
# subshell also keeps this lib's globals (_TS_NAME, CREDITED_REVIEW_SKILLS and
# every function) out of the hook's shell; a second caller that sources it
# directly gets them. Constants and functions only; sources credited-skills.sh
# at CALL time, guarded. Not model-sourced. Bash 3.2. Never records prompt text
# or args.

# _typed_slash_parse <prompt> — sets _TS_NAME to the typed name (no `/`) and
# returns 0 when, after leading whitespace, the first token is `/` +
# [A-Za-z0-9_.-]+ with at most one non-empty `prefix:`, at most 100 chars;
# else sets it empty and returns 1. Pure bash, no fork.
_typed_slash_parse() {
    local _p="${1:-}" _ws _tok
    _TS_NAME=""
    _ws="${_p%%[![:space:]]*}"
    _p="${_p#"${_ws}"}"
    case "${_p}" in /*) ;; *) return 1 ;; esac
    _tok="${_p%%[[:space:]]*}"
    _tok="${_tok#/}"
    [ -n "${_tok}" ] || return 1
    case "${_tok}" in
        *[!A-Za-z0-9_.:-]*|*:*:*|:*|*:) return 1 ;;
    esac
    [ "${#_tok}" -le 100 ] || return 1
    _TS_NAME="${_tok}"
    return 0
}

# _typed_slash_name <prompt> — prints the typed name and returns 0, or returns 1.
_typed_slash_name() {
    _typed_slash_parse "${1:-}" || return 1
    printf '%s' "${_TS_NAME}"
}

# _typed_slash_builtin_cc_ok — 0 iff the running Claude Code (acs_cc_version,
# credited-skills.sh) is at least 2.1.308. A built-in has no registry entry, and
# on 2.1.308 an UNKNOWN slash command fires UserPromptSubmit with a payload
# identical to a real one (controller probe, 2026-10-25), so the payload cannot
# show the built-in exists; the version is the only witness. 2.1.308 is the
# version the built-ins were observed on. Missing, malformed or older => 1.
# Components are validated by acs_cc_version, so the comparisons are total.
_typed_slash_builtin_cc_ok() {
    local _v _x _y _z
    _v="$(acs_cc_version)"
    [ -n "${_v}" ] || return 1
    _x="${_v%%.*}"; _z="${_v##*.}"; _y="${_v#*.}"; _y="${_y%.*}"
    [ "${_x}" -gt 2 ] && return 0
    [ "${_x}" -lt 2 ] && return 1
    [ "${_y}" -gt 1 ] && return 0
    [ "${_y}" -lt 1 ] && return 1
    [ "${_z}" -ge 308 ]
}

# _typed_slash_installed <name> <registry_path> — 0 iff <name> is a bare
# built-in on a Claude Code new enough to have it (_typed_slash_builtin_cc_ok),
# or the registry cache holds an available skill named <bare> (with a typed
# prefix: whose invoke is exactly Skill(<prefix>:<bare>)), or an available
# plugin providing the command /<bare> (with a typed prefix: named <prefix>).
# A built-in name that fails the version check still passes through a registry
# entry. Missing or unparseable registry => only the built-in branch. One jq.
_typed_slash_installed() {
    local _name="${1:-}" _reg="${2:-}" _bare _prefix=""
    [ -n "${_name}" ] || return 1
    _bare="${_name##*:}"
    case "${_name}" in *:*) _prefix="${_name%%:*}" ;; esac
    if [ -z "${_prefix}" ] && credited_review_builtin "${_bare}" && _typed_slash_builtin_cc_ok; then
        return 0
    fi
    [ -n "${_reg}" ] && [ -f "${_reg}" ] || return 1
    jq -e --arg b "${_bare}" --arg p "${_prefix}" '
        def arr(x): if (x | type) == "array" then x else [] end;
        any(arr(.skills)[]; type == "object" and .available == true and .name == $b
              and ($p == "" or .invoke == ("Skill(" + $p + ":" + $b + ")")))
        or any(arr(.plugins)[]; type == "object" and .available == true
              and any(arr(.provides.commands?)[]; . == ("/" + $b))
              and ($p == "" or .name == $p))
    ' "${_reg}" >/dev/null 2>&1
}

# typed_slash_credit <prompt_kind> <prompt> <hook_input> <plugin_root> — always 0.
# On a credited, installed typed REVIEW name, pipes the synthetic payload built
# from the FIRST JSON value of <hook_input> to the completion hook, synchronously.
typed_slash_credit() {
    local _kind="${1:-}" _prompt="${2:-}" _input="${3:-}" _root="${4:-}" _payload
    [ "${_kind}" = "prompt" ] || return 0
    [ -n "${_root}" ] || return 0
    _typed_slash_parse "${_prompt}" || return 0
    . "${_root}/hooks/lib/credited-skills.sh" 2>/dev/null \
        && command -v credited_review_skill >/dev/null 2>&1 \
        && command -v credited_review_builtin >/dev/null 2>&1 || return 0
    credited_review_skill "${_TS_NAME}" || return 0
    _typed_slash_installed "${_TS_NAME}" "${HOME}/.claude/.skill-registry-cache.json" || return 0
    _payload="$(printf '%s' "${_input}" | jq -nc --arg s "${_TS_NAME}" '
        def str(x): if (x | type) == "string" then x else "" end;
        first(inputs) | select(type == "object")
        | {tool_name: "Skill", tool_input: {skill: $s},
           session_id: str(.session_id), transcript_path: str(.transcript_path),
           cwd: str(.cwd), acs_source: "typed-slash"}' 2>/dev/null)" || return 0
    [ -n "${_payload}" ] || return 0
    # The hook run and the libs it loads come from the same root.
    printf '%s\n' "${_payload}" \
        | CLAUDE_PLUGIN_ROOT="${_root}" /bin/bash "${_root}/hooks/skill-completion-hook.sh" >/dev/null 2>&1 || true
    return 0
}
