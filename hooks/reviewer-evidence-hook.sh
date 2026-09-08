#!/bin/bash
# reviewer-evidence-hook.sh — PostToolUse on ^(Task|Agent)$
#
# Records a `reviewer-ran` milestone into the per-(repo+branch) branch ledger
# when a REVIEWER subagent is dispatched. This is the signal that
# distinguishes "the review skill was invoked" (which skill-completion-hook.sh
# already credits the instant Skill() returns its instructions) from "a
# reviewer subagent was actually spawned to do it" — NOT from "a review was
# completed". PostToolUse for `Agent`/`Task` fires on the SPAWN acknowledgement,
# not on the subagent's eventual return: measured across 23 real `Agent` calls
# in three transcripts, every `tool_result` is a ~310-330 byte "Spawned
# successfully…" message and none carries an `is_error` field. The reviewer's
# real report arrives later as a separate task notification this hook never
# sees. A reviewer that spawns and then crashes, is stopped, goes idle, or
# returns nothing is recorded identically to one that reviewed successfully.
#
# Diagnostic/advisory recorder ONLY. It emits nothing on stdout, sets no
# permissionDecision, and every failure path exits 0 silently — a recorder
# must never alter a gate decision. Deliberately NOT in _GATE_ENFORCE_LIBS.
#
# Spec: openspec/changes/observed-dispatch-telemetry/
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
# over-crediting, the direction the asymmetry note below calls dangerous. It is still
# the right trade: the alternative is the typed index, which records nothing at
# all for that shape (fail-closed only by accident) and is the defect this
# guard exists to remove.
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[
    .tool_name // "",
    ((.tool_response | objects | .is_error) // false | tostring),
    ((.tool_input | objects | .subagent_type) // "" | tostring),
    (.session_id // "" | tostring),
    ((.tool_response | objects | .agentId) // "" | tostring),
    ((.tool_input | objects | .description) // "" | tostring | gsub("[\\n\\r]"; " "))
  ] | join("\u001f")' 2>/dev/null)" || exit 0
[ -z "${_FIELDS}" ] && exit 0

# The description is parsed LAST and takes the remainder, so every field added
# here must go BEFORE it — a trailing field would be swallowed by any \x1f a
# free-text description happened to contain.
_TOOL="${_FIELDS%%$'\x1f'*}";      _R1="${_FIELDS#*$'\x1f'}"
_IS_ERROR="${_R1%%$'\x1f'*}";      _R2="${_R1#*$'\x1f'}"
_SUBAGENT="${_R2%%$'\x1f'*}";      _R3="${_R2#*$'\x1f'}"
_SID="${_R3%%$'\x1f'*}";           _R4="${_R3#*$'\x1f'}"
_AGENT_ID="${_R4%%$'\x1f'*}"
_DESC="${_R4#*$'\x1f'}"

# Only the subagent-dispatch tool. `Agent` is the current Claude Code name;
# `Task` is kept for older builds this plugin also ships to.
case "${_TOOL}" in Task|Agent) ;; *) exit 0 ;; esac

# An agent whose spawn acknowledgement reports an error was never dispatched
# successfully, so it reviewed nothing. NOTE: measured absent from all 23 real
# `Agent` payloads sampled (see header) — this leg is currently dead in
# production, and every dispatch that reaches this point is credited. Kept
# because it costs nothing and protects a future payload shape that does carry
# the field; do not delete it as unreachable.
[ "${_IS_ERROR}" = "true" ] && exit 0

# Reviewer identification. `case`, not `for x in $LIST`: unquoted scalar
# expansion does not word-split under zsh and would iterate once over the
# whole string.
#
# The predicate is deliberately TIGHT (see the asymmetry note below). This
# hook is diagnostic telemetry, not a gate (design.md D2) — but the error
# cost is still asymmetric: a MISSED review costs one un-upgraded telemetry
# field, while a WRONGLY credited non-reviewer silently records a false
# compliance signal into that same telemetry. Do not loosen this to catch
# the occasional miss.
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
        # miss costs an un-upgraded telemetry field for a branch where one
        # demonstrably did. Substring is REJECTED: it matches the noun
        # "reviewer" inside implementer task names such as "Task 3:
        # reviewer-evidence writer hook".
        #
        # Three substring arms (*"code review"*, *"Code review"*,
        # *"code-review"*) briefly shipped OR'd with the word-boundary pattern
        # and are REMOVED. They were NOT zero-recall — they also fire on "code
        # review" followed by a LETTER, which word-boundary cannot match, so
        # dropping them does lose genuine reviews ("Dispatch a code reviewer
        # for the auth changes", "code-reviewing the new observer hook"). But that
        # extra recall is exactly the noun/gerund class, and that class holds
        # genuine reviews and implementation tasks in the SAME syntactic shape
        # ("Fix the code-reviewer dispatch bug", "Task 1: remove the dead
        # code-reviewer target") — no substring can separate them, so the
        # recall can only be bought together with the false positives.
        # The asymmetry above decides it: a wrongly credited non-reviewer
        # silently records a false compliance signal in the telemetry, whereas
        # a missed review only costs one un-upgraded telemetry field. Pinned
        # by (e6).
        #
        # The one known false positive is recorded rather than silently
        # accepted, because over-crediting is the dangerous direction (see
        # above): "Task 2: review_dispatch config key" is an implementation
        # task whose subject is literally named review-dispatch, and it
        # credits with no reviewer having run.
        #
        # This is a corrected recall failure, NOT a loosening. The rule that
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
# is a recorder — a failed load costs a record, never a deny. This change does
# not touch openspec-guard.sh's own source sites.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_PLUGIN_ROOT}" ]; then
    # NOT `X="${VAR:-$(cd .. && pwd)}"`. A top-level assignment whose value comes
    # from a command substitution trips this file's blanket `trap 'exit 0' ERR`
    # AT THAT LINE when the substitution fails, killing the hook before anything
    # below it runs — the shape CLAUDE.md calls out in publish-guard.sh. Split so
    # the failure is handled rather than fatal.
    _PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)" || _PLUGIN_ROOT=""
fi
[ -n "${_PLUGIN_ROOT}" ] || exit 0
_LEDGER_OK=false
# Kept on ONE physical line: tests/test-hook-source-guards.sh classifies each
# source line by grepping single lines, so a `\`-continued guard reads to the
# lint as a bare `. lib` and is flagged.
# shellcheck source=lib/branch-ledger.sh
. "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null && command -v branch_ledger_record >/dev/null 2>&1 && _LEDGER_OK=true || true
[ "${_LEDGER_OK}" = "true" ] || exit 0

# branch_ledger_record stores "<sha> <utc-ts>", so the evidence is SHA-bound
# for free — any future reader, such as scripts/record-review-verdict.sh, can
# compare that SHA against HEAD to judge staleness without this hook doing
# anything extra.
branch_ledger_record "reviewer-ran" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Reviewer dispatch/completion JOIN (openspec/changes/reviewer-completion-
# evidence/). `reviewer-completion-hook.sh` observes that a subagent finished;
# this hook owns the classification. Neither can credit alone.
#
# NEITHER HOOK IS GUARANTEED TO RUN FIRST — measured end-to-end against both
# real hooks on CLI 2.1.236: for a BACKGROUND dispatch this one fires 1.44s
# BEFORE completion, but for a FOREGROUND dispatch it fires ~30ms AFTER it
# (3 of 3). So each side writes its own half first and then looks for the
# other; whichever runs second records the milestone. The first cut wrote here
# and read there, which is a systematic no-op for every foreground reviewer.
#
# ORDERING WITHIN THIS FILE IS ALSO LOAD-BEARING: this runs AFTER the
# reviewer-ran record, never before. Under this file's `trap 'exit 0' ERR` a
# single failing command is a silent early exit — the first draft put this
# above the record, where `wc -c < <missing file>` (a REDIRECTION failure,
# which `2>/dev/null` does not suppress) killed the hook before it wrote
# anything, silently deleting the pre-existing milestone. New best-effort work
# goes below the thing that must not be lost. See CLAUDE.md #137/#198.
_PAIR_OK=false
# Kept on ONE physical line: tests/test-hook-source-guards.sh classifies each
# source line by grepping single lines, so a `\`-continued guard reads to the
# lint as a bare `. lib` and is flagged.
# shellcheck source=lib/reviewer-pairing.sh
# The probed symbol is the LAST function the lib defines, NOT one this hook
# calls: a file truncated at a function boundary still sources cleanly, so
# probing a symbol used here would pass while a later one stayed undefined. The
# cost is that deleting or renaming that function disables the join in BOTH
# hooks rather than erroring — which is why a cell pins "the probed symbol is the
# lib's last definition" instead of leaving it to memory.
. "${_PLUGIN_ROOT}/hooks/lib/reviewer-pairing.sh" 2>/dev/null && command -v reviewer_pairing_note_mismatch >/dev/null 2>&1 && _PAIR_OK=true || true

if [ "${_PAIR_OK}" = "true" ] && [ -n "${_AGENT_ID}" ]; then
    # The key binds the credit to a (repo, branch) pair. Stored at dispatch so
    # the completion side can refuse to credit a branch the reviewer never saw:
    # a backgrounded reviewer finishes on the parent session's clock, and that
    # session is free to check out something else meanwhile.
    _PAIR_KEY="$(branch_ledger_key 2>/dev/null)" || _PAIR_KEY=""
    if [ -n "${_PAIR_KEY}" ]; then
        # HALF ONE, written BEFORE reading the other half.
        reviewer_pairing_note_dispatch "${_SID}" "${_AGENT_ID}" "${_PAIR_KEY}" || true
        # HALF TWO: did this agent already finish, on THIS branch? (foreground
        # ordering). The key comparison is not symmetry for its own sake — a
        # membership test here was a measured false-credit path: an agent-id
        # collision ALONE, with no matching branch and no ordering constraint, was
        # enough to record `reviewer-returned` at SPAWN time for a reviewer that
        # had produced nothing. Reproduced against the real hooks with a positive
        # control; pinned by a cell.
        _COMP_KEY="$(reviewer_pairing_complete_key "${_SID}" "${_AGENT_ID}")" || _COMP_KEY=""
        if [ -n "${_COMP_KEY}" ] && [ "${_COMP_KEY}" = "${_PAIR_KEY}" ]; then
            branch_ledger_record "reviewer-returned" 2>/dev/null || true
        fi
    fi
fi

exit 0
