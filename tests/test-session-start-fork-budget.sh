#!/bin/bash
# test-session-start-fork-budget.sh — pins how many external processes the
# session-start hook forks over a fixed fixture, and the behaviour the fork
# removals must preserve.
#
# Why a fork COUNT and not a wall clock: measured 2026-10-12, the hook took
# ~2.8 s with twelve plugins against a stated 200 ms budget, and a line-numbered
# `bash -x` trace attributed it to 621 forks at 3-7 ms each: 108 jq calls from
# the LSP plugin.json loop (one per manifest), 114 ls/grep/sort calls from the
# semver resolver, ~240 basename/dirname pairs in the discovery loops. Time is
# machine-dependent; the count is not, so the count is what is pinned. It is a
# CEILING: growth fails and needs a reason in the commit that raises it; a
# reduction passes and the constant is lowered when convenient. It was an
# equality ratchet from PR #348 and was re-pinned by PR #351 the same day; the
# 2026-10-12 value review kept equality only for the two totals a user pays
# (_INJECTION_BASELINE per prompt, _COMBINED_BASELINE per session start).
#
# The fixture holds what the hot loops iterate over: two marketplace plugins,
# each with a plugin.json carrying lspServers (one resolvable command, one
# missing), one with two semver version dirs where lexical and numeric order
# disagree (9.9.9 vs 10.0.0), and one user skill.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-session-start-fork-budget.sh ==="

# CEILING (see header). Measured 2026-10-12 on this fixture, traced from
# TEST_TMPDIR: 30 after the fork removals (27 jq, 1 grep, 1 dirname, 1 awk),
# from 177 before them (66 basename, 61 dirname, 35 jq, 6 grep, 4 sort, 4 ls,
# 1 awk). The remaining jq calls are one per build step over the whole
# registry, not one per discovered item; the next cut is batching those.
#
# 30 -> 33 (2026-10-12, #304): a deliberate growth. Frontmatter is now parsed
# as two tiers (external marketplace; bundled plus user) so the merge can refuse
# an external SKILL.md's role/phase/precedes/requires for a config-owned name.
# One extra parse (jq plus awk) and one jq to combine the two maps; all three
# are per build, not per item. NOT counted here: when a skill-rules.json exists
# the Step 5c fold runs one more jq (it is applied to both maps); this fixture
# ships none, so that cost is unmeasured by this ratchet.
_SS_FORK_BASELINE=33
# Floor on the trace itself: an empty or truncated trace would count 0 forks
# and read as the best possible result. The real trace is tens of thousands of
# lines; this floor only has to reject "nothing ran".
_SS_TRACE_FLOOR=2000

setup_test_env

# --- fixture ----------------------------------------------------------------
_wb="${HOME}/.claude/plugins/cache/acme/widget"
mkdir -p "${_wb}/9.9.9/skills/acs-fb-old" "${_wb}/10.0.0/skills/acs-fb-new" "${_wb}/10.0.0/.claude-plugin"
printf '%s\n' '---' 'name: acs-fb-old' 'description: Old' '---' '# O' > "${_wb}/9.9.9/skills/acs-fb-old/SKILL.md"
printf '%s\n' '---' 'name: acs-fb-new' 'description: New' '---' '# N' > "${_wb}/10.0.0/skills/acs-fb-new/SKILL.md"
printf '%s\n' '{"name":"widget","lspServers":{"w":{"command":"acs-fb-definitely-missing-binary"}}}' \
    > "${_wb}/10.0.0/.claude-plugin/plugin.json"

_tb="${HOME}/.claude/plugins/cache/acme/toolkit"
mkdir -p "${_tb}/1.2.3/skills/acs-fb-tool" "${_tb}/1.2.3/.claude-plugin"
printf '%s\n' '---' 'name: acs-fb-tool' 'description: Tool' '---' '# T' > "${_tb}/1.2.3/skills/acs-fb-tool/SKILL.md"
printf '%s\n' '{"name":"toolkit","lspServers":{"t":{"command":"sh"}}}' > "${_tb}/1.2.3/.claude-plugin/plugin.json"

mkdir -p "${HOME}/.claude/skills/acs-fb-user"
printf '%s\n' '---' 'name: acs-fb-user' 'description: User' '---' '# U' > "${HOME}/.claude/skills/acs-fb-user/SKILL.md"

# --- one traced run -----------------------------------------------------------
# From TEST_TMPDIR, not the checkout: the hook also reads the WORKSPACE it is
# launched in (its .claude-plugin/plugin.json via PWD, .claude/knowledge/index.md
# via `git rev-parse`), and those reads fork. Traced from the repo root the
# count was 36; from elsewhere 34 (review finding). The fixture, not the
# checkout, is what this file pins.
_TRACE="${TEST_TMPDIR}/trace.txt"
_OUT="${TEST_TMPDIR}/out.txt"
( cd "${TEST_TMPDIR}" && PS4='+F: ' CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash -x "${HOOK}" > "${_OUT}" 2> "${_TRACE}" < /dev/null )
_rc=$?
_trace_lines="$(wc -l < "${_TRACE}" | tr -d ' ')"
case "${_trace_lines}" in ''|*[!0-9]*) _trace_lines=0 ;; esac

if [ "${_rc}" -eq 0 ]; then
    _record_pass "hook exits 0 under the tracer"
else
    _record_fail "hook exits 0 under the tracer" "exit ${_rc}"
fi

if [ "${_trace_lines}" -ge "${_SS_TRACE_FLOOR}" ]; then
    _record_pass "trace floor: ${_trace_lines} xtrace lines (>= ${_SS_TRACE_FLOOR}), so a fork count below is a count of something"
else
    _record_fail "trace floor" "only ${_trace_lines} xtrace lines -- the hook did not run to its end, so the fork count is meaningless"
fi

# Nesting depth repeats the first PS4 character, hence `\++`.
_forks="$(grep -cE '^\++F: (jq|basename|dirname|ls|grep|sort|awk) ' "${_TRACE}" 2>/dev/null)"
case "${_forks}" in ''|*[!0-9]*) _forks=-1 ;; esac
_by_cmd="$(grep -oE '^\++F: (jq|basename|dirname|ls|grep|sort|awk) ' "${_TRACE}" | awk '{print $2}' | sort | uniq -c | sort -rn | tr '\n' ';')"

if [ "${_forks}" -lt 0 ]; then
    _record_fail "fork ratchet" "could not count forks in ${_TRACE}"
elif [ "${_forks}" -le "${_SS_FORK_BASELINE}" ]; then
    _record_pass "fork ceiling: ${_forks} jq/basename/dirname/ls/grep/sort/awk forks (ceiling ${_SS_FORK_BASELINE}) [${_by_cmd}]"
else
    _record_fail "fork ceiling" "grew to ${_forks} forks over the ${_SS_FORK_BASELINE} ceiling (+$((_forks - _SS_FORK_BASELINE))) [${_by_cmd}]. Each fork is 3-7 ms on macOS against a 200 ms budget. Batch the jq, use parameter expansion for basename/dirname, or raise the constant in the SAME commit and say why."
fi

# --- behaviour the removals must preserve ------------------------------------
_cache="${HOME}/.claude/.skill-registry-cache.json"

# Semver: numeric per component, so 10.0.0 outranks 9.9.9 (lexically smaller).
_new_inv="$(jq -r '.skills[] | select(.name == "acs-fb-new") | .invoke' "${_cache}" 2>/dev/null)"
_old_inv="$(jq -r '.skills[] | select(.name == "acs-fb-old") | .invoke' "${_cache}" 2>/dev/null)"
if [ "${_new_inv}" = "Skill(widget:acs-fb-new)" ] && [ -z "${_old_inv}" ]; then
    _record_pass "semver pick: 10.0.0 outranks 9.9.9 (numeric, not lexical)"
else
    _record_fail "semver pick" "expected only acs-fb-new from 10.0.0; got new='${_new_inv}' old='${_old_inv}'"
fi

# Discovery names: basename/dirname replacement must yield the same skill names.
_tool_inv="$(jq -r '.skills[] | select(.name == "acs-fb-tool") | .invoke' "${_cache}" 2>/dev/null)"
_user_inv="$(jq -r '.skills[] | select(.name == "acs-fb-user") | .invoke' "${_cache}" 2>/dev/null)"
if [ "${_tool_inv}" = "Skill(toolkit:acs-fb-tool)" ]; then
    _record_pass "discovery: marketplace skill named from its SKILL.md path"
else
    _record_fail "discovery (marketplace)" "got '${_tool_inv}'"
fi
if [ -n "${_user_inv}" ]; then
    _record_pass "discovery: user skill named from its SKILL.md path (${_user_inv})"
else
    _record_fail "discovery (user)" "acs-fb-user not in the registry"
fi

# LSP: one plugin's command resolves (sh) so lsp=true; the batched rewrite must
# still see both manifests.
_lsp="$(jq -r '.context_capabilities.lsp' "${_cache}" 2>/dev/null)"
if [ "${_lsp}" = "true" ]; then
    _record_pass "lsp capability: a resolvable lspServers command flips lsp=true"
else
    _record_fail "lsp capability" "expected lsp=true (toolkit's command 'sh' resolves); got '${_lsp}'"
fi

# --- partial-install diagnostic, including an EMPTY plugin name -------------
# A second run with the resolvable plugin removed, so no command resolves and
# the "LSP (partial install)" line renders. A third manifest carries
# `"name": ""`: the batched rows once used TAB as the field separator, and
# `read` collapses consecutive tabs, so the empty name shifted the command into
# the name slot and the row was dropped silently (review finding). The old
# per-file loop processed it with an empty name; this pins that it still does.
rm -rf "${_tb}"
_eb="${HOME}/.claude/plugins/cache/acme/emptyname"
mkdir -p "${_eb}/1.0.0/skills/acs-fb-empty" "${_eb}/1.0.0/.claude-plugin"
printf '%s\n' '---' 'name: acs-fb-empty' 'description: E' '---' '# E' > "${_eb}/1.0.0/skills/acs-fb-empty/SKILL.md"
printf '%s\n' '{"name":"","lspServers":{"e":{"command":"acs-fb-also-missing-binary"}}}' > "${_eb}/1.0.0/.claude-plugin/plugin.json"
_OUT2="${TEST_TMPDIR}/out2.txt"
( cd "${TEST_TMPDIR}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash "${HOOK}" > "${_OUT2}" 2>/dev/null < /dev/null )
_ctx2="$(jq -r '.hookSpecificOutput.additionalContext // ""' "${_OUT2}" 2>/dev/null)"
if printf '%s' "${_ctx2}" | grep -qF "LSP (partial install)"; then
    _record_pass "partial-install diagnostic renders when no lspServers command resolves"
else
    _record_fail "partial-install diagnostic" "no 'LSP (partial install)' line in the hook output"
fi
if printf '%s' "${_ctx2}" | grep -qF "widget needs acs-fb-definitely-missing-binary"; then
    _record_pass "partial-install diagnostic names the plugin and its missing binary"
else
    _record_fail "partial-install diagnostic (named plugin)" "$(printf '%s' "${_ctx2}" | grep -F 'LSP (partial' | cut -c1-200)"
fi
if printf '%s' "${_ctx2}" | grep -qF "acs-fb-also-missing-binary"; then
    _record_pass "a manifest with an empty name still contributes its missing binary (no field collapse)"
else
    _record_fail "empty-name manifest" "its missing binary is absent from: $(printf '%s' "${_ctx2}" | grep -F 'LSP (partial' | cut -c1-200)"
fi

teardown_test_env
print_summary
