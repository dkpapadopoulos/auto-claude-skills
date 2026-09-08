#!/bin/bash
# reviewer-completion-hook.sh — SubagentStop
#
# Records a `reviewer-returned` milestone into the per-(repo+branch) branch
# ledger when a REVIEWER subagent runs to COMPLETION. This is the signal
# `reviewer-evidence-hook.sh` cannot give: that hook runs on `PostToolUse` for
# `^(Task|Agent)$`, and for a BACKGROUNDED dispatch that payload is a launch
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
# THE JOIN IS SYMMETRIC, AND THAT IS THE WHOLE DESIGN. Classification lives in
# the dispatch hook (it owns the measured `description` predicate); this hook
# owns the completion fact. Neither can credit alone, and NEITHER IS GUARANTEED
# TO RUN FIRST — measured end-to-end against the real hooks on CLI 2.1.236:
#
#   background dispatch : DISPATCH fires 1.44s BEFORE completion
#   foreground dispatch : COMPLETION fires ~30ms BEFORE dispatch (3 of 3)
#
# A dispatch-writes-then-completion-reads design is therefore a systematic
# no-op for FOREGROUND dispatches — measured, not theorised: the first cut of
# this hook recorded `reviewer-ran` and no `reviewer-returned` for a foreground
# reviewer. So each hook writes its own half FIRST and then looks for the other;
# whichever runs second completes the join. Do not "simplify" this back into a
# one-directional lookup.
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

_INPUT="$(cat 2>/dev/null)"
[ -z "${_INPUT}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# One jq fork, \x1f-joined (the repo's field separator; never \n).
#
# `last_assistant_message` is read ONLY to test emptiness and is deliberately
# the LAST field: it is free-form model output that can contain any byte,
# including \x1f, so anything appended after it would be swallowed. Its VALUE is
# never stored — see the "what is not recorded" note at the ledger write.
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[
    (.hook_event_name // "" | tostring),
    (.session_id // "" | tostring),
    (.agent_id // "" | tostring),
    (.last_assistant_message // "" | tostring)
  ] | join("\u001f")' 2>/dev/null)" || exit 0
[ -z "${_FIELDS}" ] && exit 0

_EVENT="${_FIELDS%%$'\x1f'*}";  _R1="${_FIELDS#*$'\x1f'}"
_SID="${_R1%%$'\x1f'*}";        _R2="${_R1#*$'\x1f'}"
_AID="${_R2%%$'\x1f'*}"
_LAST="${_R2#*$'\x1f'}"

# Registered on SubagentStop only, but a hooks.json edit that widens the
# registration must not silently start crediting on another event.
[ "${_EVENT}" = "SubagentStop" ] || exit 0

# A subagent that emitted no final message did not return a review. Measured:
# the CLI carries the subagent's final text inline in this payload, so this
# costs no extra work. It under-credits an interrupted reviewer, which is the
# safe direction for a fidelity signal.
[ -n "${_LAST}" ] || exit 0

# #137 source-guard form: source + command -v + flag. The probed symbol is the
# LAST function the lib defines, not the first one used: a file truncated at a
# function boundary still sources cleanly, so probing an early definition would
# leave a later one undefined and the command-not-found would trip the ERR trap.
# Pinned by a cell — if a function is appended to the lib, the probe must move. A bare `. lib` under
# `trap 'exit 0' ERR` is a silent early exit, and `[ -f ]` proves existence, not
# source success. Safe here because this hook is a recorder — a failed load
# costs a record, never a deny.
_PAIR_OK=false
# Kept on ONE physical line: tests/test-hook-source-guards.sh classifies each
# source line by grepping single lines, so a `\`-continued guard reads to the
# lint as a bare `. lib` and is flagged.
#
# The `&&`-guard covers the SOURCE'S OWN exit status, not a command failing
# inside the sourced file (#192). reviewer-pairing.sh only defines functions —
# it executes nothing at load — so there is no such command to fail.
# shellcheck source=lib/reviewer-pairing.sh
. "${_PLUGIN_ROOT}/hooks/lib/reviewer-pairing.sh" 2>/dev/null && command -v reviewer_pairing_note_mismatch >/dev/null 2>&1 && _PAIR_OK=true || true
[ "${_PAIR_OK}" = "true" ] || exit 0

_LEDGER_OK=false
# shellcheck source=lib/branch-ledger.sh
. "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null && command -v branch_ledger_record >/dev/null 2>&1 && _LEDGER_OK=true || true
[ "${_LEDGER_OK}" = "true" ] || exit 0

# The ledger key binds the credit to a (repo, branch) pair. It is resolved HERE
# so it can be compared against the key recorded at dispatch — see the branch
# check below, which is the reason this hook computes a key at all rather than
# letting branch_ledger_record derive one implicitly.
_KEY="$(branch_ledger_key 2>/dev/null)" || _KEY=""
[ -n "${_KEY}" ] || exit 0

# HALF ONE: publish the completion fact, unconditionally on reaching here and
# BEFORE reading the other half. A completion record is not a credit — the
# dispatch hook still has to have classified this agent as a reviewer — so
# recording every completed subagent here is not over-crediting, it is the join
# key the other side needs when IT runs second.
# `|| true` is load-bearing, not decoration: this returns non-zero whenever
# the append does not happen (size ceiling reached, unwritable ~/.claude), and
# a bare failing call under this file's `trap 'exit 0' ERR` would terminate the
# hook right here — silently skipping the join below and killing every credit
# for the rest of the session, with no diagnostic. Found by a mutation that
# was masked by exactly this early exit.
reviewer_pairing_note_complete "${_SID}" "${_AID}" "${_KEY}" || true

# HALF TWO: was this agent dispatched as a reviewer, and on THIS branch?
_DKEY="$(reviewer_pairing_dispatch_key "${_SID}" "${_AID}")" || _DKEY=""
# DEFENCE IN DEPTH, and honestly so: the branch comparison below ALSO rejects an
# absent record (an empty key can never equal a real one), so mutating this line
# away breaks no test. It is kept because it states the actual precondition —
# "this agent was dispatched as a reviewer" — rather than leaving correctness to
# depend on the coincidence that "" never compares equal.
[ -n "${_DKEY}" ] || exit 0

# BRANCH BINDING. branch_ledger_record derives its key from the cwd/branch AT
# CALL TIME, and a BACKGROUNDED reviewer completes on the parent session's
# clock — the session is free to `git checkout` a different branch while it
# runs. Crediting then would write `reviewer-returned` into the ledger of a
# branch the reviewer never looked at: not a miss but a WRONG-TARGET HIT, and
# the push gate treats ledger records as durable cross-session evidence. A
# mismatch therefore records NOTHING and leaves a diagnostic line instead.
# Under-crediting a legitimate review whose session moved on is the accepted
# cost; writing into the dispatch-time ledger dir directly would credit a
# branch this process cannot verify it is even on.
if [ "${_DKEY}" != "${_KEY}" ]; then
    reviewer_pairing_note_mismatch "${_SID}" "${_AID}" "${_DKEY}" "${_KEY}" || true
    exit 0
fi

# The recorded sha is the DISPATCH-time commit, passed explicitly — NOT HEAD at
# call time. This is the one place the "SHA-bound for free" wording inherited
# from the dispatch hook would be wrong: a backgrounded reviewer finishes while
# the session keeps committing, so HEAD here can name a tree the reviewer never
# read, and ledger records are consumed with HEAD-or-ancestor acceptance — an
# over-late sha silently covers commits nothing reviewed. That is the over-claim
# #181 removed from verdicts, and it would make this milestone LESS sha-accurate
# than the `reviewer-ran` it is meant to strengthen.
#
# An absent dispatch sha (a record written before the field existed) falls back
# to HEAD, i.e. the older, less precise behaviour — never to a fabricated value.
#
# Residual, stated: if HEAD moved between dispatch and completion this artifact
# has no way to SAY so; it records the reviewed commit, which is the honest
# lower bound, not a straddle marker. The key is sha1(origin remote URL, branch) — NOT the path — so two
# worktrees of the same repo on the same branch share a key, while a review
# recorded on a task branch and a push made from an integration branch do not,
# and a detached HEAD re-keys on every commit. Those misses are safe (a reader
# simply finds no record) but they are the normal shape of the repo's own
# agent-team-execution pattern; do not read a missing record as "no review".
#
# What is NOT recorded, deliberately: the reviewer's output text. The payload
# carries it inline and it would make the strongest-looking evidence, but it is
# unbounded model output that can quote the diff, secrets, or private memory
# content into a file that outlives the session. This repo already ships
# `hooks/publish-guard.sh` and `scripts/memory-leak-check.sh` because that class
# of content leaking outbound is a known risk, and that scanner watches only
# `~/.claude/projects/*/memory/` — a ledger holding raw reviewer text would be a
# second surface it does not know exists. The IMPLEMENT shadow corpus settled
# the same trade the same way: "raw command text is never written;
# transcript_path is the adjudication pointer."
_DSHA="$(reviewer_pairing_dispatch_sha "${_SID}" "${_AID}")" || _DSHA=""
branch_ledger_record "reviewer-returned" "" "${_DSHA}" 2>/dev/null || true

exit 0
