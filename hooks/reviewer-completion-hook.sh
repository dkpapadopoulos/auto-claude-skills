#!/bin/bash
# reviewer-completion-hook.sh — SubagentStop
#
# Records a `reviewer-returned` milestone into the per-(repo+branch) branch
# ledger when a REVIEWER subagent runs to COMPLETION. This is the signal
# `reviewer-evidence-hook.sh` cannot give: that hook runs on `PostToolUse` for
# `^(Task|Agent)$`, and for a backgrounded dispatch that payload is a launch
# acknowledgement (measured on CLI 2.1.236: `status:"async_launched"`,
# `content:null`), so a reviewer that spawns and then crashes, is stopped, goes
# idle, or returns nothing is recorded identically to one that finished.
#
# What this milestone DOES mean: a reviewer-shaped subagent ran to completion
# and emitted a final message. What it does NOT mean: that the output was a real
# review, that it examined this diff, that any finding was correct, or that
# anything was acted on. A model can still dispatch a reviewer prompted to
# rubber-stamp. The honest label is "observed completion", never "reviewed" —
# do not restate it as the latter anywhere it is read.
#
# Diagnostic/advisory recorder ONLY. It emits nothing on stdout, sets no
# permissionDecision, and every failure path exits 0 silently — a recorder must
# never alter a gate decision. Deliberately NOT in _GATE_ENFORCE_LIBS. No gate
# reads `reviewer-returned` as of this change.
#
# Spec: openspec/changes/reviewer-completion-evidence/
# Bash 3.2 compatible.

trap 'exit 0' ERR
set -uo pipefail

# _pair_file <session_id> — path of the dispatch-time pairing file, or nothing.
# The session id becomes a filename component, so it is validated as a single
# path-safe segment rather than trusted: the payload is harness-supplied, but a
# recorder must not be the thing that turns a surprising value into a write
# outside ~/.claude. Naming mirrors _SESSION_TOKEN ("session-<id>") so the
# session-start GC excludes the live session with a plain `! -name` match.
_pair_file() {
    local sid="${1:-}"
    [ -n "$sid" ] || return 1
    case "$sid" in
        *[!A-Za-z0-9._-]*|.|..) return 1 ;;
    esac
    printf '%s' "${HOME}/.claude/.skill-reviewer-dispatch-session-${sid}"
}

_INPUT="$(cat 2>/dev/null)"
[ -z "${_INPUT}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# One jq fork, \x1f-joined (the repo's field separator; never \n).
#
# `last_assistant_message` is read ONLY to test emptiness and is deliberately
# the LAST field: it is free-form model output that can contain any byte,
# including \x1f, so anything appended after it would be swallowed. Its VALUE is
# never recorded — see the "what is not recorded" note at the ledger write.
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[
    (.hook_event_name // "" | tostring),
    (.session_id // "" | tostring),
    (.agent_id // "" | tostring),
    (.agent_type // "" | tostring),
    (.last_assistant_message // "" | tostring)
  ] | join("\u001f")' 2>/dev/null)" || exit 0
[ -z "${_FIELDS}" ] && exit 0

_EVENT="${_FIELDS%%$'\x1f'*}";  _R1="${_FIELDS#*$'\x1f'}"
_SID="${_R1%%$'\x1f'*}";        _R2="${_R1#*$'\x1f'}"
_AID="${_R2%%$'\x1f'*}";        _R3="${_R2#*$'\x1f'}"
_ATYPE="${_R3%%$'\x1f'*}"
_LAST="${_R3#*$'\x1f'}"

# Registered on SubagentStop only, but a hooks.json edit that widens the
# registration must not silently start crediting on another event.
[ "${_EVENT}" = "SubagentStop" ] || exit 0

# A subagent that emitted no final message did not return a review. Measured:
# the CLI carries the subagent's final text inline in this payload, so this
# costs no extra work. It under-credits an interrupted reviewer, which is the
# safe direction for a fidelity signal.
[ -n "${_LAST}" ] || exit 0

[ -n "${_AID}" ] || exit 0

# Reviewer identification, two arms, deliberately asymmetric.
#
# ARM 1 — allowlist. `agent_type` arrives verbatim and plugin-qualified
# (measured: "pr-review-toolkit:code-reviewer", "general-purpose", "Explore"),
# so the allowlist `reviewer-evidence-hook.sh` applies to `subagent_type`
# transfers here unchanged and needs no pairing.
#
# ARM 2 — general-purpose. superpowers' own requesting-code-review dispatches
# general-purpose from a reviewer template, so an allowlist alone would
# false-negative on the ecosystem's documented pattern.
#
# The word-boundary DESCRIPTION predicate is deliberately NOT reused here, even
# though the subagent's task prompt is reachable via `agent_transcript_path`.
# That predicate (`*[Rr]eview|*[Rr]eview[!a-zA-Z]*`, measured 9/9 recall at 1/7
# false positives) was fitted on the short dispatch `description` label. Its
# second arm matches "review" ANYWHERE followed by a non-letter, so against
# multi-paragraph prompt text it structurally degenerates into the substring
# variant that measured 4/7 false positives — i.e. re-pointing it at the prompt
# would silently ship the widening that variant was rejected for. Instead the
# `agent_id` recorded at dispatch is looked up: an exact key, no heuristic, and
# the predicate stays on the input it was measured against.
#
# The lookup cannot be replaced by reading the parent transcript. Measured
# in-hook: at SubagentStop time the parent transcript contains ZERO lines
# mentioning `agent_id` (the `tool_result` carrying it is written afterwards),
# while the subagent's own transcript is already readable. The link exists only
# post-hoc, so a dispatch-time writer is required.
_IS_REVIEWER=false
case "${_ATYPE}" in
    pr-review-toolkit:code-reviewer|pr-review-toolkit:silent-failure-hunter|\
    pr-review-toolkit:pr-test-analyzer|pr-review-toolkit:comment-analyzer|\
    pr-review-toolkit:type-design-analyzer|feature-dev:code-reviewer)
        _IS_REVIEWER=true ;;
    general-purpose)
        # A MISS records nothing. The alternative — a weaker milestone on a miss
        # — would be indistinguishable from a genuine reviewer whose dispatch
        # went unrecorded, and the missing population is dominated by ordinary
        # implementation subagents, so a weaker record would be mostly noise
        # wearing an evidence label.
        #
        # Absent / unreadable file is a MISS, not an error: this hook can be
        # newer than the dispatch that produced the pairing (the dispatch may
        # predate the plugin version that writes it), and a recorder must
        # degrade to "no record", never to a fabricated one.
        _PAIR="$(_pair_file "${_SID}")" || _PAIR=""
        if [ -n "${_PAIR}" ] && [ -f "${_PAIR}" ]; then
            # -x -F: the agent id is matched as a whole literal line, so no
            # value in the file can be read as a pattern or a prefix.
            grep -qxF -- "${_AID}" "${_PAIR}" 2>/dev/null && _IS_REVIEWER=true
        fi ;;
esac
[ "${_IS_REVIEWER}" = "true" ] || exit 0

# #137 source-guard form: source + command -v + flag. A bare `. lib` under
# `trap 'exit 0' ERR` is a silent early exit, and `[ -f ]` proves existence, not
# source success. Safe here because this hook is a recorder — a failed load
# costs a record, never a deny.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_LEDGER_OK=false
# Kept on ONE physical line: tests/test-hook-source-guards.sh classifies each
# source line by grepping single lines, so a `\`-continued guard reads to the
# lint as a bare `. lib` and is flagged.
# shellcheck source=lib/branch-ledger.sh
. "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null && command -v branch_ledger_record >/dev/null 2>&1 && _LEDGER_OK=true || true
[ "${_LEDGER_OK}" = "true" ] || exit 0

# branch_ledger_record stores "<sha> <utc-ts>", so the evidence is SHA-bound for
# free. The key is sha1(origin remote URL, branch) — NOT the path — so two
# worktrees of the same repo on the same branch share a key, while a review
# recorded on a task branch and a push made from an integration branch do not,
# and a detached HEAD re-keys on every commit. Those misses are safe (a reader
# simply finds no record) but they are the normal shape of the repo's own
# agent-team-execution pattern; do not read a missing record as "no review".
#
# What is NOT recorded, deliberately: the reviewer's output text. The payload
# carries it inline and it would make the strongest-looking evidence, but it is
# unbounded model output that can quote the diff, secrets, or private memory
# content, and this repo already ships `hooks/publish-guard.sh` because exactly
# that class of content leaking outbound is a known risk. The ledger stores a
# sha and a timestamp; keep it that way.
branch_ledger_record "reviewer-returned" 2>/dev/null || true

exit 0
