#!/usr/bin/env bash
# The consultation guard must never disarm the push gate.
#
# This asserts the GUARD'S DECISION, end to end, and that is the whole point of the
# file. The activation hook's consultation guard hides a composition chain from the
# rendered output. An earlier version delivered that by skipping the chain WALK -- and
# because the walker is what writes ~/.claude/.skill-composition-state-<token>, and
# openspec-guard.sh gates its entire chain block on that file existing, the result was
# that `deny:chain-review` and `deny:chain-verify` stopped running altogether.
#
# Measured on that version, with review evidence and a clean verdict in place:
#   `git push origin HEAD` after "commit and push this, but ask codex first"
#       DENY  ->  allow
# Four other phrasings flipped identically, as did two ordinary agent-team prompts.
#
# The unit-level assertions in tests/test-consultation-routing.sh could not catch it:
# they asserted "no chain state exists", which is exactly the bypass's precondition.
# Only a guard-level assertion distinguishes "the chain was hidden from the user" from
# "the gate stopped running". Do not replace this with a check on the state file.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-consultation-bypass.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — consultation bypass NOT checked"; exit 0
fi

_OLDHOME="$HOME"
_cleanup() { HOME="$_OLDHOME"; export HOME; [ -n "${_H:-}" ] && rm -rf "${_H}"; }
trap _cleanup EXIT

# Each case starts from a FRESH session: the bypass only reaches the gate when no
# composition state has been written yet, which is the ordinary shape of picking work
# back up on an existing branch.
_new_session() {
    _H="$(mktemp -d /tmp/pg-consult-XXXXXX)"
    export HOME="${_H}"
    mkdir -p "${HOME}/.claude"
    _TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"   # basename "t" -> token "session-t"
    _TOK="session-t"

    # Registry with everything available, so routing is a decision and not an install gap.
    python3 - "${PROJECT_ROOT}" "${HOME}" <<'PY'
import json, sys
reg = json.load(open(sys.argv[1] + "/config/default-triggers.json"))
for s in reg["skills"]:
    s.update(available=True, enabled=True)
open(sys.argv[2] + "/.claude/.skill-registry-cache.json", "w").write(json.dumps(reg))
PY

    # Both GLOBAL legs satisfied, so the global fail-closed gate cannot be the reason
    # for a denial. That isolates the composition-chain checks as the only thing the
    # bypass removes -- without this the test would pass for the wrong reason.
    local _head; _head="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
    jq -nc --arg s "${_head}" \
        '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
        > "${HOME}/.claude/.skill-project-verified-${_TOK}"
    jq -nc '["requesting-code-review"]' \
        > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
}

_turn() {  # drive the REAL activation hook, as a user turn would
    jq -nc --arg p "$1" --arg t "${_TPATH}" '{prompt:$p, transcript_path:$t}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" >/dev/null 2>&1
}

_turn_capture() {  # same, but return the rendered context so suppression is checkable
    jq -nc --arg p "$1" --arg t "${_TPATH}" '{prompt:$p, transcript_path:$t}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

_push() {  # drive the REAL push gate
    jq -nc --arg tp "${_TPATH}" --arg c "${1:-git push origin HEAD}" \
        '{transcript_path:$tp, tool_input:{command:$c}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null
}

# --- 1. The exploit shape: a PURE consultation turn, then a push -----------------
# These prompts MUST classify consultation-only, or this block tests nothing. An
# earlier draft used "commit and push this, but ask codex first" and friends, and
# every cell passed with the bypass deliberately re-introduced: the dev-work veto now
# matches `commit`/`push`/`ship`, so those prompts are MIXED, the guard never fires on
# them, and the walker runs either way. They were pinning the predicate fix while
# appearing to pin the walker fix.
#
# The real exploit needs no push verb in the prompt at all. The user asks for an
# opinion; the push is a separate command in a later tool call. That turn is what
# suppressed the chain state, and the gate read the absence as "no chain to check".
# Each prompt must ALSO anchor a chain, or there is nothing for the gate to check and
# the push legitimately allows. That precondition is asserted per prompt rather than
# assumed: a prompt that stops anchoring (a trigger edit, a scoring change) would
# otherwise turn its cell green while testing nothing. One candidate was dropped during
# authoring for exactly this -- "what would another model say about this tradeoff"
# selects no process skill, writes no chain, and its push correctly allows.
for p in "ask codex to weigh in on this approach" \
         "get a second opinion from one other model on this schema design" \
         "ask gemini how it would approach this" \
         "get another llm's opinion on how we should architect this"; do
    _new_session
    _rendered="$(_turn_capture "$p")"
    # PRECONDITION 1: the consultation path actually fired. Without this the whole
    # block can stay green while the guard never runs -- a future veto change could
    # reclassify every fixture as MIXED, the walker would render normally, the push
    # would still deny for ordinary reasons, and the file would silently stop testing
    # its subject. "A chain was anchored and the push denied" is true in that world too.
    assert_not_contains "PRECONDITION suppression fired: ${p:0:30}" \
        "Composition:" "${_rendered:-<empty>}"
    # PRECONDITION 2: a chain exists to be checked. A prompt anchoring nothing has no
    # chain obligation, and its push correctly allows.
    assert_equals "PRECONDITION chain anchored: ${p:0:30}" "true" \
        "$([ -f "${HOME}/.claude/.skill-composition-state-${_TOK}" ] && echo true || echo false)"
    out="$(_push)"
    # The denial must be the CHAIN's, not any denial. An unrelated gate, a setup
    # failure, or an unconditional-deny regression would satisfy a bare '"deny"'.
    assert_contains "consultation turn still denies: ${p:0:30}" \
        '"deny"' "${out:-<empty>}"
    # The setup satisfies the REVIEW leg (invocation evidence), so it is chain Check 2 --
    # VERIFY -- that must fire. Naming it matters: a bare '"deny"' is also produced by
    # the review check, by routing-governance, and by an unconditional-deny regression.
    assert_contains "denial is chain-specific (verify): ${p:0:26}" \
        "verification-before-completion" "${out:-<empty>}"
    _cleanup
done

# --- 1b. The OTHER chain check, exercised independently -------------------------
# With both milestones missing, deleting the verify check would leave review denying
# every push and vice versa, so a single always-denies case cannot tell which check is
# alive. Drop the review evidence and the denial must move to the review check.
_new_session
rm -f "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
_turn "ask codex to weigh in on this approach"
out="$(_push)"
assert_contains "review leg denies when its evidence is absent" \
    "requesting-code-review" "${out:-<empty>}"
_cleanup

# --- 2. Ordinary development prompts, which the predicate must also not disarm ---
# These are agent-team shaped: the highest-autonomy workflow in the registry. They
# were classified consultation-only by an earlier predicate because `agents` matched
# bare, and they flipped the gate with entirely non-adversarial phrasing.
for p in "let two agents handle the backfill and merge the results" \
         "run each agent on its own worktree then open a PR"; do
    _new_session
    _turn "$p"
    out="$(_push)"
    assert_contains "agent-team turn still denies: ${p:0:38}" \
        '"deny"' "${out:-<empty>}"
    _cleanup
done

# --- 3. Positive control: the gate is capable of allowing ------------------------
# Without this, every assertion above is satisfied by a gate that denies unconditionally
# and the file would pin nothing. Recording the review milestone in the durable ledger
# AND completing the chain's gating milestones is what a genuinely finished branch looks
# like; the same harness must then allow.
_new_session
_turn "commit and push this, but ask codex first"
_COMP="${HOME}/.claude/.skill-composition-state-${_TOK}"
if [ -f "${_COMP}" ]; then
    # Mark the two gating milestones complete, which is the state a real REVIEW+VERIFY
    # cycle leaves behind.
    jq -c '.completed = ((.completed // []) + ["requesting-code-review","verification-before-completion"] | unique_by(.))' \
        "${_COMP}" > "${_COMP}.tmp" 2>/dev/null && mv "${_COMP}.tmp" "${_COMP}"
fi
out="$(_push)"
assert_not_contains "control: completed gating milestones => gate can allow" \
    '"deny"' "${out:-}"
_cleanup

# --- 4. The state file is the mechanism, asserted as a mechanism note ------------
# Not a substitute for the decision assertions above: this records WHY they hold, so a
# future reader changing the guard knows which artifact the gate depends on.
_new_session
_turn "commit and push this, but ask codex first"
_COMP="${HOME}/.claude/.skill-composition-state-${_TOK}"
assert_equals "composition state is written for a consultation turn" \
    "true" "$([ -f "${_COMP}" ] && echo true || echo false)"
_cleanup

# --- 5. KNOWN GAP, pinned: cancellation waives the chain checks -----------------
# Not introduced by the consultation guard -- measured identical on the tree that
# predates it. Recorded here because it is the SAME mechanism the guard's bypass used:
# no state file means openspec-guard.sh skips its chain block entirely.
#
# A bare pure-cancel prompt ("cancel", "stop", "nevermind") deletes the composition
# state. Measured across all eight combinations of (review evidence, clean verdict,
# cancelled), it changes the outcome in EXACTLY ONE: with both already present. So it
# is not "type cancel to skip the gates" -- it downgrades chain-VERIFY to
# verdict-VERIFY, and this repo holds those to be different things.
#
# Pinned rather than fixed: a fix is a decision about cancellation semantics, and the
# obvious one would false-block a user who genuinely cancelled and genuinely verified.
# These cells fail if the gap WIDENS -- if cancelling ever helps without that evidence.
for _ev in "none" "review-only" "verdict-only"; do
    _new_session
    case "${_ev}" in
        none)        rm -f "${HOME}/.claude/.skill-invocation-evidence-${_TOK}" \
                           "${HOME}/.claude/.skill-project-verified-${_TOK}" ;;
        review-only) rm -f "${HOME}/.claude/.skill-project-verified-${_TOK}" ;;
        verdict-only) rm -f "${HOME}/.claude/.skill-invocation-evidence-${_TOK}" ;;
    esac
    _turn "let's design and build a new caching layer"
    _turn "cancel"
    out="$(_push)"
    assert_contains "cancel does NOT waive the gate without full evidence (${_ev})" \
        '"deny"' "${out:-<empty>}"
    _cleanup
done

print_summary
