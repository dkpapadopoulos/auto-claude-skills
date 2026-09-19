#!/usr/bin/env bash
# test-attest-remedy-reachable.sh — issue #248.
#
# THE DEFECT. Three gate messages tell an agent to record a deliberate skip
# with `phase_attest <step> "<reason>"`. The IMPLEMENT advisory and the
# outbound DESIGN/PLAN message named the function with NO source line at all;
# `skill-gate.sh` carried one, built from two paths that BOTH fail anywhere but
# this repo:
#
#   source "$(git rev-parse --show-toplevel)/hooks/lib/phase-attest.sh"   # the USER's repo — no hooks/lib
#   source "$CLAUDE_PLUGIN_ROOT/hooks/lib/phase-attest.sh"                # unset in a model Bash turn
#
# Measured from a model Bash turn at plugin 3.90.1, in a scratch repo standing
# in for an external one: `CLAUDE_PLUGIN_ROOT` is unset and the pair resolves to
# nothing, so `phase_attest` is `not found`. The remedy is unreachable exactly
# where the leg fires — 73 attestation-satisfied records in this repo, 0
# elsewhere, against 26 would-block records elsewhere.
#
# That is load-bearing for the IMPLEMENT deny-flip pre-registration, which
# classifies a deny resolved by one truthful attestation as a `true_catch` on
# the premise that attesting was possible.
#
# THE FIX. The guard already resolved the answer: `_PLUGIN_ROOT` is an absolute
# path to the running plugin. Emit THAT, rather than a recipe the reader must
# re-derive in a shell where the inputs are missing.
#
# WHY THIS TEST RUNS THE REMEDY INSTEAD OF MATCHING ITS TEXT. A string
# assertion would have passed on the broken version too — it contained
# `phase_attest` and even a `source` line. The only assertion that distinguishes
# a usable remedy from a plausible one is executing it and asking whether the
# function exists.
#
# AND IT RUNS IT IN BOTH SHELLS. The remedy is executed by the MODEL, whose
# Bash tool is the user's shell (zsh), while every hook runs under bash. A
# remedy verified only under bash can be broken for every real user:
# phase-attest.sh locates its sibling via `${BASH_SOURCE:-}`, which is EMPTY in
# zsh. bash is kept as the explicit control.
#
# Bash 3.2 compatible (macOS default).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-attest-remedy-reachable.sh ==="
echo ""

WORK="$(mktemp -d "${TMPDIR:-/tmp}/acs-remedy.XXXXXXXX")" || WORK=""
if [ -z "${WORK}" ] || [ ! -d "${WORK}" ]; then
    echo "FATAL: could not create a temp dir; refusing to run" >&2
    exit 1
fi
trap 'rm -rf "${WORK}"' EXIT

# An "external repo": a real git repo that is NOT this plugin and has no hooks/lib.
EXT="${WORK}/external-repo"
mkdir -p "${EXT}"
( cd "${EXT}" && git init -q . && printf 'x\n' > a.txt && git add a.txt \
  && git -c user.email=t@t -c user.name=t commit -q -m init )

# ---------------------------------------------------------------------------
# run_remedy <shell> <remedy-command>
# Executes the remedy the way an agent would: in the external repo, with
# CLAUDE_PLUGIN_ROOT unset, and reports whether phase_attest became callable.
# ---------------------------------------------------------------------------
run_remedy() {
    local sh="$1" remedy="$2"
    ( cd "${EXT}" && env -u CLAUDE_PLUGIN_ROOT HOME="${WORK}/home" \
        "${sh}" -c "${remedy%%;*}; command -v phase_attest >/dev/null 2>&1 && echo REACHABLE || echo UNREACHABLE" \
        2>/dev/null ) | tail -1
}
mkdir -p "${WORK}/home/.claude"

# ---------------------------------------------------------------------------
# 1. The OLD idiom is unreachable — the red control.
# ---------------------------------------------------------------------------
# Without this, "the new remedy works" would not establish that the old one
# failed, and the whole change could be a no-op dressed as a fix.
echo "--- red control: the pre-#248 idiom ---"
OLD_REMEDY='source "$(git rev-parse --show-toplevel)/hooks/lib/phase-attest.sh" 2>/dev/null || source "$CLAUDE_PLUGIN_ROOT/hooks/lib/phase-attest.sh" 2>/dev/null'
# zsh is the shell the MODEL pastes into, so a silent skip would leave the
# headline claim untested while the file still reports green. Announce it, the
# way tests/test-phase-attest-shell-portability.sh does.
SHELLS=""
for _sh in /bin/bash /bin/zsh; do
    [ -x "${_sh}" ] && SHELLS="${SHELLS} ${_sh}"
done
case "${SHELLS}" in
    *zsh*) : ;;
    *) echo "WARNING: zsh not installed — the leg that carries this file's headline claim did NOT run." >&2 ;;
esac
for _sh in ${SHELLS}; do
    assert_equals "old idiom is UNREACHABLE in an external repo ($(basename "${_sh}"))" \
        "UNREACHABLE" "$(run_remedy "${_sh}" "${OLD_REMEDY}")"
done

# ---------------------------------------------------------------------------
# 2. Extract the remedy from each REAL message and execute it.
# ---------------------------------------------------------------------------
# The remedies are read out of the hooks' own rendered text, never hand-copied:
# a hand-copy only ever agrees with this test's idea of the message.
echo ""
echo "--- the shipped remedies, executed ---"

# _remedy_from <text> — pull the `source '...phase-attest.sh'` command out.
# Single-quoted: the emitted path must be INERT when pasted, so double quotes
# (which expand `$…` and execute backticks) are not an accepted form here.
_remedy_from() {
    printf '%s' "${1:-}" | sed -n "s/.*\(source '[^']*phase-attest\.sh'\).*/\1/p" | head -1
}

# The guard renders _PLUGIN_ROOT into its messages, so render them for real.
GUARD_REMEDY="$(cd "${PROJECT_ROOT}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash -c '
    _PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    '"$(sed -n '/^_shq()/,/^}/p;/^_attest_remedy()/,/^}/p' "${PROJECT_ROOT}/hooks/openspec-guard.sh")"'
    command -v _attest_remedy >/dev/null 2>&1 && _attest_remedy executing-plans
' 2>/dev/null)"

if [ -n "${GUARD_REMEDY}" ]; then
    _record_pass "extracted _attest_remedy from openspec-guard.sh"
    SRC="$(_remedy_from "${GUARD_REMEDY}")"
    assert_not_empty "the guard's remedy contains a source command" "${SRC}"
    for _sh in ${SHELLS}; do
        assert_equals "guard remedy is REACHABLE in an external repo ($(basename "${_sh}"))" \
            "REACHABLE" "$(run_remedy "${_sh}" "${SRC}")"
    done
else
    _record_fail "extracted _attest_remedy from openspec-guard.sh" \
        "the helper is missing or renamed — every cell below is vacuous"
fi

# --- skill-gate.sh: extract the remedy from a REAL deny and run it too ------
# This is the message an agent sees when a GATING milestone is missing, so it
# is the one whose reachability matters most. Rendered by driving an actual
# deny, never by reading the source string.
SG_HOME="${WORK}/sg-home"; mkdir -p "${SG_HOME}/.claude"
SG_TOKEN="session-remedy"
printf '%s' "${SG_TOKEN}" > "${SG_HOME}/.claude/.skill-session-token"
printf '{"chain":["brainstorming","writing-plans","subagent-driven-development","requesting-code-review"],"completed":[],"current_index":0}\n' \
    > "${SG_HOME}/.claude/.skill-composition-state-${SG_TOKEN}"
printf '["brainstorming"]\n' > "${SG_HOME}/.claude/.skill-invocation-evidence-${SG_TOKEN}"
SG_OUT="$(printf '{"tool_name":"Skill","tool_input":{"skill":"superpowers:subagent-driven-development"},"transcript_path":""}' \
    | HOME="${SG_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${PROJECT_ROOT}" \
      /bin/bash "${PROJECT_ROOT}/hooks/skill-gate.sh" 2>/dev/null)"
SG_MSG="$(printf '%s' "${SG_OUT}" | jq -r '.systemMessage // ""' 2>/dev/null)"
if [ -n "${SG_MSG}" ]; then
    _record_pass "drove a real skill-gate deny to render its remedy"
    SG_SRC="$(_remedy_from "${SG_MSG}")"
    assert_not_empty "the skill-gate remedy contains a source command" "${SG_SRC}"
    for _sh in ${SHELLS}; do
        assert_equals "skill-gate remedy is REACHABLE in an external repo ($(basename "${_sh}"))" \
            "REACHABLE" "$(run_remedy "${_sh}" "${SG_SRC}")"
    done
else
    _record_fail "drove a real skill-gate deny to render its remedy" \
        "the hook produced no systemMessage — the cells below it are vacuous"
fi

# ---------------------------------------------------------------------------
# 3. Every message that names phase_attest must carry a source command.
# ---------------------------------------------------------------------------
# A lint, because the defect was three sites and the next one will be a fourth.
echo ""
echo "--- lint: no message names phase_attest without saying where it lives ---"
NAMING=""
# EVERY hook, not a hardcoded pair. Measured in review: adding a fourth site to
# hooks/skill-activation-hook.sh left this file 11/11 green while CLAUDE.md
# claimed the lint covered it — and that fourth site already existed.
for _f in "${PROJECT_ROOT}"/hooks/*.sh; do
    while IFS= read -r line; do
        case "${line}" in
            *_attest_remedy*|*'_attest_remedy()'*) continue ;;
        esac
        case "${line}" in
            *phase_attest\ *)
                case "${line}" in
                    # `source %s` is the helper's own emitter line, which IS
                    # saying where — it just says it with a placeholder.
                    *phase-attest.sh*|*_attest_remedy*|*'source %s'*) : ;;
                    *) NAMING="${NAMING}${NAMING:+
}$(basename "${_f}"): ${line}" ;;
                esac
                ;;
        esac
    done <<EOF
$(grep -n 'phase_attest ' "${_f}" 2>/dev/null | grep -v 'command -v\|phase_attested')
EOF
done
if [ -z "${NAMING}" ]; then
    _record_pass "every message naming phase_attest also says where to source it"
else
    _record_fail "every message naming phase_attest also says where to source it" \
        "unreachable remedies:
${NAMING}"
fi

# ---------------------------------------------------------------------------
# 4. The CONFIG preconditions — the site this fix originally missed.
# ---------------------------------------------------------------------------
# `hooks/skill-activation-hook.sh` renders a skill's `precondition` into the
# mandatory guidance channel, and two of them name `phase_attest`. That text
# reaches EVERY IMPLEMENT-phase prompt in EVERY repo — far more often than the
# push-gate advisory this file started with — and `executing-plans` is the exact
# remedy the IMPLEMENT deny-flip pre-registration assumes is available.
#
# The renderer has no substitution of its own, so the config carries a
# {{PLUGIN_ROOT}} placeholder and the hook fills it in.
echo ""
echo "--- config preconditions carry a resolvable path ---"
for _cfg in "${PROJECT_ROOT}/config/default-triggers.json" "${PROJECT_ROOT}/config/fallback-registry.json"; do
    _base="$(basename "${_cfg}")"
    _bare="$(grep -c "record it: phase_attest\|record the skip: phase_attest" "${_cfg}" 2>/dev/null | tr -d ' ')"
    assert_equals "${_base}: no precondition names phase_attest with no source" "0" "${_bare}"
    _ph="$(grep -c '{{PLUGIN_ROOT}}/hooks/lib/phase-attest.sh' "${_cfg}" 2>/dev/null | tr -d ' ')"
    if [ "${_ph}" -ge 2 ]; then
        _record_pass "${_base}: both preconditions carry the placeholder (${_ph})"
    else
        _record_fail "${_base}: both preconditions carry the placeholder" "found ${_ph}, expected >= 2"
    fi
done

# The renderer must actually substitute, and must escape a path containing a
# single quote — the one character single quotes cannot contain. Driven through
# the REAL substitution block extracted from the hook, never a hand-copy.
_SUBST="$(sed -n "/POSIX single-quote escaping, fork-free/,/_cprecond=\"\${_cprecond\/\//p" "${PROJECT_ROOT}/hooks/skill-activation-hook.sh")"
if printf '%s' "${_SUBST}" | grep -q 'PLUGIN_ROOT'; then
    _record_pass "extracted the real {{PLUGIN_ROOT}} substitution from the hook"
    # Built from the HOOK'S OWN LINES, not a hand-copy. The first version
    # pasted the escaping into this file and therefore only ever agreed with
    # itself: mutating the hook's `_pr_esc=` line left every cell below green.
    # `sed` lifts the three live lines out of the hook and this wrapper runs
    # exactly those.
    _ESC_LINES="$(sed -n '/_sq="."[[:space:]]*;[[:space:]]*_bs=/,/_cprecond="\${_cprecond\/\//p' \
        "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" | sed 's/^[[:space:]]*//')"
    if [ "$(printf '%s' "${_ESC_LINES}" | grep -c '_pr_esc=')" -ne 1 ]; then
        _record_fail "lifted the hook's own escaping lines" \
            "expected exactly one _pr_esc= line, got $(printf '%s' "${_ESC_LINES}" | grep -c '_pr_esc=') — the cells below would test a copy, not the hook"
    else
        _record_pass "lifted the hook's own escaping lines"
    fi
    {
        printf '#!/bin/bash\n'
        printf '%s\n' "_cprecond=\"record it: source '{{PLUGIN_ROOT}}/hooks/lib/phase-attest.sh'; phase_attest executing-plans.\""
        printf '%s\n' "${_ESC_LINES}"
        printf '%s\n' 'printf "%s\n" "${_cprecond}"'
    } > "${WORK}/render.sh"
    _render_precond() { PLUGIN_ROOT="$1" /bin/bash "${WORK}/render.sh"; }

    assert_contains "a plain path substitutes" \
        "source '/p/ok/hooks/lib/phase-attest.sh'" "$(_render_precond /p/ok)"
    assert_contains "a path with a space stays quoted" \
        "source '/p a/b/hooks/lib/phase-attest.sh'" "$(_render_precond '/p a/b')"
    assert_contains "a path with a single quote is escaped, not broken" \
        "'/p'\\''q/hooks/lib/phase-attest.sh'" "$(_render_precond "/p'q")"
    # The whole point of single-quoting: a pasted remedy must execute nothing.
    rm -f "${WORK}/PWN"
    _pwn_line="$(_render_precond "/p\$(touch ${WORK}/PWN)x")"
    /bin/bash -c "${_pwn_line#record it: }" >/dev/null 2>&1 || true
    if [ -e "${WORK}/PWN" ]; then
        _record_fail "a pasted remedy executes nothing from the plugin path" "command substitution in the path RAN"
    else
        _record_pass "a pasted remedy executes nothing from the plugin path"
    fi
else
    _record_fail "extracted the real {{PLUGIN_ROOT}} substitution from the hook" \
        "not found — the renderer changed shape and the cells below are vacuous"
fi

print_summary
