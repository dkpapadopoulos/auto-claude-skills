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
#
# EVERY nested read goes through `| objects |`. `.a.b` is a TYPED INDEX in jq,
# not a lookup: it EXITS 5 when `.a` is an array, string or number, and the
# `|| exit 0` below then turns this recorder permanently silent — empty stdout,
# exit 0, no record, forever. An array of content blocks is a plausible shape
# for `tool_response` (agent OUTPUT); `tool_input` is schema-fixed and lower
# risk, but it is the same class and gets the same guard. `tostring` before
# `gsub` for the same reason: gsub on a non-string description errors and kills
# the record just as thoroughly.
#
# TRADE, accepted deliberately: for a NON-OBJECT `tool_response` the error
# signal is unobservable, and `// false` defaults it to success — so an ERRORED
# array-shaped agent return is now CREDITED as a review that ran. That is
# over-crediting, the direction the D1 note below calls dangerous. It is still
# the right trade: the alternative is the typed index, which records nothing at
# all for that shape (fail-closed only by accident) and is the defect this
# guard exists to remove.
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[
    .tool_name // "",
    ((.tool_response | objects | .is_error) // false | tostring),
    (if ((.tool_response | objects | has("is_error")) // false)
     then "present" else "absent" end),
    ((.tool_input | objects | .subagent_type) // "" | tostring),
    ((.tool_input | objects | .description) // "" | tostring | gsub("[\\n\\r]"; " "))
  ] | join("\u001f")' 2>/dev/null)" || exit 0
[ -z "${_FIELDS}" ] && exit 0

# The description is parsed LAST and takes the remainder, so every field added
# here must go BEFORE it — a trailing field would be swallowed by any \x1f a
# free-text description happened to contain.
_TOOL="${_FIELDS%%$'\x1f'*}";      _R1="${_FIELDS#*$'\x1f'}"
_IS_ERROR="${_R1%%$'\x1f'*}";      _R2="${_R1#*$'\x1f'}"
_ERR_FIELD="${_R2%%$'\x1f'*}";     _R3="${_R2#*$'\x1f'}"
_SUBAGENT="${_R3%%$'\x1f'*}"
_DESC="${_R3#*$'\x1f'}"

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
        #
        # WORD-BOUNDARY match — neither prefix nor substring. Measured against
        # the real `description` strings dispatched while building this change
        # (9 genuine reviewer dispatches, 7 non-reviewer):
        #
        #   prefix      [Rr]eview*                          3/9 credited, 0/7 false pos
        #   substring   *[Rr]eview*                         9/9 credited, 4/7 false pos
        #   word-bound  *[Rr]eview|*[Rr]eview[!a-zA-Z]*     9/9 credited, 1/7 false pos
        #
        # Prefix shipped first and missed two thirds of real reviews ("Task 1
        # review: spec + quality", "Scoped re-review of Task 1 fix") — a
        # predicate that blind measures itself, not agent compliance, and every
        # miss enters the shadow corpus as "no reviewer ran" for a branch where
        # one demonstrably did. Substring is REJECTED: it matches the noun
        # "reviewer" inside implementer task names such as "Task 3:
        # reviewer-evidence writer hook".
        #
        # Three substring arms (*"code review"*, *"Code review"*,
        # *"code-review"*) briefly shipped OR'd with the word-boundary pattern
        # and are REMOVED. They were NOT zero-recall — they also fire on "code
        # review" followed by a LETTER, which word-boundary cannot match, so
        # dropping them does lose genuine reviews ("Dispatch a code reviewer
        # for the auth changes", "code-reviewing the new gate leg"). But that
        # extra recall is exactly the noun/gerund class, and that class holds
        # genuine reviews and implementation tasks in the SAME syntactic shape
        # ("Fix the code-reviewer dispatch bug", "Task 1: remove the dead
        # code-reviewer target") — no substring can separate them, so the
        # recall can only be bought together with the false positives.
        # D1's asymmetry decides it: while the leg is advisory a wrongly
        # credited non-reviewer silently corrupts the measurement corpus,
        # whereas a missed review costs one spurious advisory. Pinned by (e6).
        #
        # The one known false positive is recorded rather than silently
        # accepted, because over-crediting is the dangerous direction (D1):
        # "Task 2: review_dispatch config key" is an implementation task whose
        # subject is literally named review-dispatch, and it credits with no
        # reviewer having run.
        #
        # This is a corrected recall failure, NOT a loosening. D1's rule that
        # the predicate ships tight still stands: do not widen further, and do
        # not add audit/inspect/check/critique keywords.
        case "${_DESC}" in
            *[Rr]eview|*[Rr]eview[!a-zA-Z]*)
                _IS_REVIEWER=true ;;
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

# SIDECAR: whether the payload carried `.tool_response.is_error` at all.
#
# The credit above is `is_error // false`, so an ABSENT field still credits —
# a crashed reviewer can be recorded as a review that ran. Probing the harness
# for the real shape would mean editing the user's global settings, so instead
# each return records present-vs-absent and the corpus answers the question
# itself over time. openspec-guard.sh::_reviewer_is_error_field reads this file
# and resolves "unknown" without it, which is what left that precondition
# satisfied by nothing.
#
# A SIDECAR, not a field in the milestone file (the #133 precedent): that file
# is format-frozen as "<sha> <utc-ts>" for branch_ledger_sha and the guard's
# staleness comparison. Written AFTER branch_ledger_record because
# branch_ledger_dir is pure — it prints a path and never mkdirs, so the
# directory only exists once the record has been written. Last write wins; this
# is a per-branch property, not a log.
_LEDGER_DIR=""
if command -v branch_ledger_dir >/dev/null 2>&1; then
    _LEDGER_DIR="$(branch_ledger_dir 2>/dev/null)" || _LEDGER_DIR=""
fi
if [ -n "${_LEDGER_DIR}" ] && [ -d "${_LEDGER_DIR}" ]; then
    _SC="${_LEDGER_DIR}/reviewer-ran.is-error-field"
    printf '%s\n' "${_ERR_FIELD}" > "${_SC}.tmp.$$" 2>/dev/null \
        && mv "${_SC}.tmp.$$" "${_SC}" 2>/dev/null || true
fi

exit 0
