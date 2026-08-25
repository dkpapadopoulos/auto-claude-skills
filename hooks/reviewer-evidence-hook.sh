#!/bin/bash
# reviewer-evidence-hook.sh — PostToolUse on ^(Task|Agent)$
#
# Records a `reviewer-ran` milestone into the per-(repo+branch) branch ledger
# when a REVIEWER subagent returns successfully. This is the signal that
# distinguishes "the review skill was invoked" (which skill-completion-hook.sh
# already credits the instant Skill() returns its instructions) from "a
# reviewer actually ran".
#
# Diagnostic/advisory recorder ONLY. It emits nothing on stdout, sets no
# permissionDecision, and every failure path exits 0 silently — a recorder
# must never alter a gate decision. Deliberately NOT in _GATE_ENFORCE_LIBS.
#
# Spec: openspec/changes/reviewer-dispatch-and-evidence/
# Bash 3.2 compatible.

trap 'exit 0' ERR
set -uo pipefail

_INPUT="$(cat 2>/dev/null)"
[ -z "${_INPUT}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# One jq fork, \x1f-joined (the repo's field separator; never \n, which a
# free-text description legitimately contains).
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[
    .tool_name // "",
    (.tool_response.is_error // false | tostring),
    (.tool_input.subagent_type // ""),
    (.tool_input.description // "" | gsub("[\\n\\r]"; " "))
  ] | join("\u001f")' 2>/dev/null)" || exit 0
[ -z "${_FIELDS}" ] && exit 0

_TOOL="${_FIELDS%%$'\x1f'*}";      _R1="${_FIELDS#*$'\x1f'}"
_IS_ERROR="${_R1%%$'\x1f'*}";      _R2="${_R1#*$'\x1f'}"
_SUBAGENT="${_R2%%$'\x1f'*}"
_DESC="${_R2#*$'\x1f'}"

# Only the subagent-dispatch tool. `Agent` is the current Claude Code name;
# `Task` is kept for older builds this plugin also ships to.
case "${_TOOL}" in Task|Agent) ;; *) exit 0 ;; esac

# An errored or aborted agent reviewed nothing.
[ "${_IS_ERROR}" = "true" ] && exit 0

# Reviewer identification. `case`, not `for x in $LIST`: unquoted scalar
# expansion does not word-split under zsh and would iterate once over the
# whole string.
#
# The predicate is deliberately TIGHT (see design.md D1). While the gate leg
# is advisory the error cost is asymmetric: a MISSED review costs one spurious
# advisory, but a WRONGLY credited non-reviewer silently enters the corpus as
# compliance and biases the pre-registered deny-flip toward flipping. Do not
# loosen this to quiet advisories.
_IS_REVIEWER=false
case "${_SUBAGENT}" in
    pr-review-toolkit:code-reviewer|pr-review-toolkit:silent-failure-hunter|\
    pr-review-toolkit:pr-test-analyzer|pr-review-toolkit:comment-analyzer|\
    pr-review-toolkit:type-design-analyzer|feature-dev:code-reviewer)
        _IS_REVIEWER=true ;;
    general-purpose)
        # superpowers' own requesting-code-review dispatches general-purpose
        # from a reviewer template, so an allowlist alone would false-negative
        # on the ecosystem's documented pattern. general-purpose is also the
        # workhorse for implementation, hence the intent gate.
        case "${_DESC}" in
            [Rr]eview*|*"code review"*|*"Code review"*|*"code-review"*) _IS_REVIEWER=true ;;
        esac ;;
esac
[ "${_IS_REVIEWER}" = "true" ] || exit 0

# #137 source-guard form: source + command -v + flag. A bare `. lib` under
# `trap 'exit 0' ERR` is a silent early exit, and `[ -f ]` proves existence,
# not source success. Safe to use the command -v form HERE because this hook
# is a recorder — a failed load costs a record, never a deny. The guard-side
# site in openspec-guard.sh must NOT gain this check (see design.md D6).
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_LEDGER_OK=false
# Kept on ONE physical line: tests/test-hook-source-guards.sh classifies each
# source line by grepping single lines, so a `\`-continued guard reads to the
# lint as a bare `. lib` and is flagged.
# shellcheck source=lib/branch-ledger.sh
. "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null && command -v branch_ledger_record >/dev/null 2>&1 && _LEDGER_OK=true || true
[ "${_LEDGER_OK}" = "true" ] || exit 0

# branch_ledger_record stores "<sha> <utc-ts>", so the evidence is SHA-bound
# for free (design.md D8) — the gate leg surfaces staleness when that SHA
# differs from HEAD, exactly as _ledger_has already does for other milestones.
branch_ledger_record "reviewer-ran" 2>/dev/null || true

exit 0
