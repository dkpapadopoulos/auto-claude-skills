#!/usr/bin/env bash
# test-push-gate-degradation-advisory.sh — issue #198.
#
# The push gate is deliberately fail-OPEN on infrastructure error: when a
# gate-enforcement lib cannot load, the legs that depend on it are skipped and
# the push is allowed. That is the right direction — a check that cannot run
# must never block. What was wrong is that it happened in COMPLETE SILENCE:
# measured at da651b5, four distinct lib-load faults produced EMPTY stdout,
# which the harness cannot distinguish from a deliberate allow. The user is
# told nothing, so a permanently degraded plugin install looks exactly like a
# clean gate that keeps passing.
#
# This test pins the advisory AND, equally importantly, pins that adding it
# changed no `permissionDecision` anywhere in the matrix.
#
# WHY A REAL CHECKOUT, NOT A /tmp COPY OF THE GUARD: openspec-guard.sh derives
# `_PLUGIN_ROOT` from `$0` when CLAUDE_PLUGIN_ROOT is unset, so a bare /tmp
# copy silently changes which libs it can find and fabricates the very
# difference under test. Every run below sets CLAUDE_PLUGIN_ROOT explicitly at
# a full copied tree.
#
# WHY A CLEAN VERDICT IS SEEDED: this repo IS a routing repo and this branch's
# own diff touches hooks/, so routing-governance denies every push unless a
# clean verdict covers HEAD. Without the seed, the fault cells below would be
# masked by that deny instead of showing the advisory — the test would be red
# for a reason unrelated to what it measures. tests/test-push-gate-ledger.sh
# carries the same seeding block for the same reason.
#
# Bash 3.2 compatible (macOS default). No associative arrays.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures/guard-lib-fault"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-degradation-advisory.sh ==="
echo ""

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgd-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"     # basename "t" -> token "session-t"
_TOK="session-t"

# Disposable plugin root — libs get broken in here, never in the checkout.
_TROOT="$(mktemp -d /tmp/pgd-root-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks"  "${_TROOT}/hooks"
cp -R "${PROJECT_ROOT}/config" "${_TROOT}/config" 2>/dev/null || true

_cleanup() { export HOME="$_OLDHOME"; rm -rf "${_TROOT}"; }
trap _cleanup EXIT

_HEAD="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
jq -nc --arg s "${_HEAD}" \
    '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
    > "${HOME}/.claude/.skill-project-verified-${_TOK}"

_input() {
    jq -n --arg tp "$_TPATH" --arg cmd "${1:-git push origin HEAD}" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}

# run [plugin_root] — always from the real checkout, explicit CLAUDE_PLUGIN_ROOT.
run() {
    ( cd "${PROJECT_ROOT}" && _input | \
        CLAUDE_PLUGIN_ROOT="${1:-${_TROOT}}" bash "${_TROOT}/hooks/openspec-guard.sh" 2>/dev/null )
}

# Live ~/.claude state is mutable, so a single run can differ from the next for
# reasons unrelated to the fault. Every cell runs twice and the pair must agree.
# The mismatch is recorded as a FAILURE here rather than encoded in the returned
# string: a marker that no assertion looks for is not a check, and substring
# assertions over a concatenated "a|b" are asymmetric — `assert_not_contains`
# gets stricter while `assert_contains` gets looser, so half of them would pass
# on a mismatch. Caught in review of this file.
run_stable() {
    local a b
    a="$(run "${1:-${_TROOT}}")"
    b="$(run "${1:-${_TROOT}}")"
    if [ "$a" != "$b" ]; then
        _record_fail "guard output is deterministic across two runs" \
            "run1=[${a}] run2=[${b}]"
    fi
    printf '%s' "$a"
}

# The advisory's own payload, not merely "some additionalContext exists".
# _STALE_MSG writers (e.g. EVALUATOR SURFACE) can populate the same field, so a
# bare `assert_contains "additionalContext"` passes with this feature entirely
# removed — proven by mutation in review.
_advisory_text() { printf '%s' "${1:-}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || printf ''; }
_has_decision()  { printf '%s' "${1:-}" | jq -e '.hookSpecificOutput | has("permissionDecision")' >/dev/null 2>&1 && echo true || echo false; }

_restore_ledger() { cp "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh" "${_TROOT}/hooks/lib/branch-ledger.sh"; }
_restore_verdict() { cp "${PROJECT_ROOT}/hooks/lib/verdict.sh"       "${_TROOT}/hooks/lib/verdict.sh"; }

# ---------------------------------------------------------------------------
# Cell 5 — healthy control. Must be BYTE-IDENTICAL to the recorded baseline and
# must not mention degradation. This is the no-regression clause of the issue's
# A/B contract; the fixture is the pinned never-delete artifact and is captured
# from the PRE-change guard under exactly this seeded state.
# ---------------------------------------------------------------------------
out="$(run_stable)"
if [ -f "${FIXTURES}/healthy-control.json" ]; then
    assert_equals "healthy control is byte-identical to the pinned baseline" \
        "$(cat "${FIXTURES}/healthy-control.json")" "${out}"
else
    _record_fail "healthy-control fixture exists" "missing ${FIXTURES}/healthy-control.json"
fi
assert_not_contains "healthy control emits no degradation advisory" \
    "GATE DEGRADED" "${out:-}"
assert_equals "healthy control still reaches a decision" "true" "$(_has_decision "${out}")"

# ---------------------------------------------------------------------------
# Cell 2 — branch-ledger.sh absent. Every ledger leg and the whole global
# fail-closed gate stop being enforced. Baseline: empty stdout.
# ---------------------------------------------------------------------------
rm -f "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"; adv="$(_advisory_text "${out}")"
assert_contains "absent ledger lib => degradation advisory"   "GATE DEGRADED"    "${adv:-<empty>}"
assert_contains "advisory names the lib that did not load"    "branch-ledger.sh" "${adv:-<empty>}"
assert_contains "advisory names what stopped being enforced"  "global fail-closed gate" "${adv:-<empty>}"
assert_equals   "absent ledger lib still falls OPEN"          "false" "$(_has_decision "${out}")"
_restore_ledger

# ---------------------------------------------------------------------------
# Cell 3 — branch-ledger.sh returns non-zero mid-source. `[ -f "$lib" ]` says
# the file is fine; the source still fails. Baseline: empty stdout.
# ---------------------------------------------------------------------------
printf '\nreturn 1\n' >> "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"; adv="$(_advisory_text "${out}")"
assert_contains "failing ledger source => degradation advisory" "GATE DEGRADED"    "${adv:-<empty>}"
assert_contains "advisory names the lib that did not load"      "branch-ledger.sh" "${adv:-<empty>}"
assert_equals   "failing ledger source still falls OPEN"        "false" "$(_has_decision "${out}")"
_restore_ledger

# ---------------------------------------------------------------------------
# Cell 1 — plugin root unresolvable. This is the memory-evidenced shape: the
# guard resolved its root to a directory with no hooks/lib, so session-token.sh
# is unreachable too and the hook exits before any gate runs. Covering only
# branch-ledger.sh would leave THIS case silent, which is why the token path is
# in scope.
# ---------------------------------------------------------------------------
#
# One dead root is ONE fault. Per-lib notes would describe the same cause four
# times, repeat the same long path four times, and make the MOST severe state
# (nothing ran at all) read exactly like the mildest (one leg off). The
# collapsed note must therefore name the root and say plainly that nothing was
# gated — asserted here so a regression to per-lib spam fails.
_EMPTY_ROOT="$(mktemp -d /tmp/pgd-empty-XXXXXX)"
out="$(run_stable "${_EMPTY_ROOT}")"; adv="$(_advisory_text "${out}")"
assert_contains "unresolvable plugin root => degradation advisory" "GATE DEGRADED"  "${adv:-<empty>}"
assert_contains "collapsed note names the dead root"               "${_EMPTY_ROOT}" "${adv:-<empty>}"
assert_not_contains "one cause is reported once, not per lib"      "branch-ledger.sh" "${adv:-}"
assert_equals   "unresolvable plugin root still falls OPEN"        "false" "$(_has_decision "${out}")"
# No token resolved here, so this exit really does precede every gate — the
# strong claim is licensed on THIS path and only here (see cell 1c).
assert_contains "no-token exit may say the entire gate was skipped" \
    "ENTIRE push gate was skipped" "${adv:-<empty>}"
# ...and must NOT also claim identity fell back to the singleton. Nothing
# resolved here, so "fell back" and "any check that DID run" are both false.
# A regression introduced when the identity clause was hardcoded into the
# collapsed string: the two sentences then contradicted each other in the same
# advisory. The clause is now conditional on a token having actually resolved.
assert_not_contains "no-token exit does not also claim a singleton fallback" \
    "another conversation" "${adv:-}"
# push-only gates are not knowable at this exit (it runs before _gc_is_push is
# resolved), so they must be omitted rather than guessed.
assert_not_contains "no-token exit does not guess push-only gates" \
    "routing-governance" "${adv:-}"
rm -rf "${_EMPTY_ROOT}"

# ---------------------------------------------------------------------------
# Cell 1c — the collapsed note must not OVERCLAIM. hooks/lib is gone, but a
# session token resolves via the singleton and a composition state exists, so
# the chain REVIEW/VERIFY gates still run: they read `.completed` straight out
# of the state file with jq and need no lib at all.
#
# The paired deny below is the proof, not decoration: with the milestone
# missing the gate DENIES with hooks/lib absent, so a message claiming nothing
# was gated would be flatly false. The first cut of this collapse said exactly
# that. Replacing a silent under-report with a confident over-report is the
# worse failure — it tells the user to distrust a gate that is still holding.
# ---------------------------------------------------------------------------
_DEAD_ROOT="$(mktemp -d /tmp/pgd-dead-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks" "${_DEAD_ROOT}/hooks"; rm -rf "${_DEAD_ROOT}/hooks/lib"
printf 'session-t' > "${HOME}/.claude/.skill-session-token"
printf '%s' '{"chain":["brainstorming","requesting-code-review","verification-before-completion"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-08-12T10:00:00Z"}' \
    > "${HOME}/.claude/.skill-composition-state-session-t"
out="$( ( cd "${PROJECT_ROOT}" && printf '{"tool_input":{"command":"git push origin HEAD"}}' | \
    CLAUDE_PLUGIN_ROOT="${_DEAD_ROOT}" bash "${_DEAD_ROOT}/hooks/openspec-guard.sh" 2>/dev/null ) )"
assert_equals "lib-free chain gate STILL denies with hooks/lib absent" \
    "true" "$(_has_decision "${out}")"
# Now satisfy the chain so no deny fires and the advisory is the only output.
printf '%s' '{"chain":["brainstorming","requesting-code-review","verification-before-completion"],"current_index":2,"completed":["brainstorming","requesting-code-review","verification-before-completion"],"updated_at":"2026-08-12T10:00:00Z"}' \
    > "${HOME}/.claude/.skill-composition-state-session-t"
out="$( ( cd "${PROJECT_ROOT}" && printf '{"tool_input":{"command":"git push origin HEAD"}}' | \
    CLAUDE_PLUGIN_ROOT="${_DEAD_ROOT}" bash "${_DEAD_ROOT}/hooks/openspec-guard.sh" 2>/dev/null ) )"
adv="$(_advisory_text "${out}")"
assert_contains     "dead root still announces degradation"          "GATE DEGRADED" "${adv:-<empty>}"
assert_not_contains "collapsed note must NOT claim nothing was gated" \
    "not gated at all" "${adv:-}"
assert_not_contains "collapsed note must NOT claim the entire gate was skipped" \
    "ENTIRE push gate was skipped" "${adv:-}"
assert_contains     "collapsed note scopes its claim to library-backed checks" \
    "library-backed" "${adv:-<empty>}"
# The collapse must not swallow the identity warning. With hooks/lib gone the
# token falls back to the shared singleton, which under concurrent sessions
# names ANOTHER conversation — so a chain check that "passed" may have been
# satisfied by someone else's state. That is the one degradation here that
# turns a deny into an allow, and the per-lib note carrying it is exactly what
# the early-return suppresses. Caught in re-verification.
assert_contains     "collapsed note keeps the wrong-identity warning" \
    "another conversation" "${adv:-<empty>}"
# A push may name the push-only gates.
assert_contains     "collapsed note names push-only gates on a PUSH" \
    "routing-governance" "${adv:-<empty>}"

# ---- 1d: the same dead root, but a MERGE. routing-governance and
# mutate-then-push are both _gc_is_push-gated, so naming them here would assert
# that a gate which never applies to merges had been disabled. The per-lib
# verdict note already splits on this; the collapsed path bypassed that
# discipline because the text was composed before push/merge was known.
out="$( ( cd "${PROJECT_ROOT}" && printf '{"tool_input":{"command":"gh pr merge 123 --squash"}}' | \
    CLAUDE_PLUGIN_ROOT="${_DEAD_ROOT}" bash "${_DEAD_ROOT}/hooks/openspec-guard.sh" 2>/dev/null ) )"
adv_merge="$(_advisory_text "${out}")"
assert_contains     "merge still announces degradation"            "GATE DEGRADED"     "${adv_merge:-<empty>}"
assert_not_contains "merge does NOT name routing-governance"       "routing-governance" "${adv_merge:-}"
assert_not_contains "merge does NOT name mutate-then-push"         "mutate-then-push"   "${adv_merge:-}"
# The phase-evidence leg has no _gc_is_push gate and DOES fire on merges, so it
# must still be named — otherwise the fix would have over-corrected.
assert_contains     "merge still names the phase-evidence leg"     "phase-evidence"     "${adv_merge:-<empty>}"
rm -rf "${_DEAD_ROOT}"
rm -f "${HOME}/.claude/.skill-composition-state-session-t" "${HOME}/.claude/.skill-session-token"

# ---------------------------------------------------------------------------
# Cell 1b — session-token.sh alone is unloadable, hooks/lib otherwise intact,
# and no singleton exists. The per-lib note still applies here (the root is not
# dead), AND the message must state the real consequence.
#
# The generic note says the identity "fell back to the shared singleton", which
# is only true when that fallback found something — in which case the guard
# CONTINUES and the gates still run. Reaching the empty-token exit means it
# found nothing: no token, no gate, nothing enforced. Pinning the stronger
# wording because the weaker one understated a total bypass (review finding).
# ---------------------------------------------------------------------------
rm -f "${_TROOT}/hooks/lib/session-token.sh"
rm -f "${HOME}/.claude/.skill-session-token"
out="$(run_stable)"; adv="$(_advisory_text "${out}")"
assert_contains "absent token lib => degradation advisory"   "GATE DEGRADED"     "${adv:-<empty>}"
assert_contains "advisory names the token lib"               "session-token.sh"  "${adv:-<empty>}"
assert_contains "advisory states the ENTIRE gate was skipped" "ENTIRE push gate was skipped" "${adv:-<empty>}"
assert_equals   "absent token lib still falls OPEN"          "false" "$(_has_decision "${out}")"
cp "${PROJECT_ROOT}/hooks/lib/session-token.sh" "${_TROOT}/hooks/lib/session-token.sh"

# ---------------------------------------------------------------------------
# Cell 7 — verdict.sh absent while the gate otherwise PASSES. Cell 6 below
# shows why this cell is needed: when a deny fires, the guard's one-JSON-object
# contract means the advisory cannot also be emitted, so the verdict advisory
# is only observable on a passing push.
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
branch_ledger_record "requesting-code-review"         "${PROJECT_ROOT}"
branch_ledger_record "verification-before-completion" "${PROJECT_ROOT}"
rm -f "${_TROOT}/hooks/lib/verdict.sh"
out="$(run_stable)"; adv="$(_advisory_text "${out}")"
assert_contains "absent verdict lib on a passing push => advisory" "GATE DEGRADED" "${adv:-<empty>}"
assert_contains "advisory names the verdict lib"                   "verdict.sh"    "${adv:-<empty>}"
assert_contains "advisory names what stopped being enforced"       "routing-governance" "${adv:-<empty>}"
assert_equals   "absent verdict lib still falls OPEN"              "false" "$(_has_decision "${out}")"
_restore_verdict

# ---------------------------------------------------------------------------
# Cell 8 — git-command.sh. This is the ONLY gate-enforcement lib whose loss
# actually removes a DENY: without it `command_git_mutate_before_push` is
# undefined and the mutate-then-push check (a combined `git commit && git push`,
# which pre-exec evidence can never cover) silently stops firing. Measured with
# every other gate satisfied: deny with the lib present, ALLOW without it.
#
# It was missed in the first cut of this change, which is worse than an
# ordinary gap — an advisory that presents itself as the inventory of what
# stopped being enforced, while omitting the one entry that costs a deny, is a
# false all-clear on its most severe item.
# ---------------------------------------------------------------------------
_MUTATE_CMD='git commit -m x && git push origin main'
out="$(run "" )" # keep evidence seeded; measure the mutate-then-push pair below
out_with="$( ( cd "${PROJECT_ROOT}" && _input "${_MUTATE_CMD}" | \
    CLAUDE_PLUGIN_ROOT="${_TROOT}" bash "${_TROOT}/hooks/openspec-guard.sh" 2>/dev/null ) )"
assert_equals "mutate-then-push DENIES while git-command.sh is present" \
    "true" "$(_has_decision "${out_with}")"
rm -f "${_TROOT}/hooks/lib/git-command.sh"
out_without="$( ( cd "${PROJECT_ROOT}" && _input "${_MUTATE_CMD}" | \
    CLAUDE_PLUGIN_ROOT="${_TROOT}" bash "${_TROOT}/hooks/openspec-guard.sh" 2>/dev/null ) )"
adv="$(_advisory_text "${out_without}")"
assert_equals   "removing git-command.sh drops that deny (the reason this must be announced)" \
    "false" "$(_has_decision "${out_without}")"
assert_contains "advisory names git-command.sh"                  "git-command.sh"  "${adv:-<empty>}"
assert_contains "advisory names the check that stopped running"  "mutate-then-push" "${adv:-<empty>}"
cp "${PROJECT_ROOT}/hooks/lib/git-command.sh" "${_TROOT}/hooks/lib/git-command.sh"

# ---------------------------------------------------------------------------
# Cell 9 — phase-evidence.sh. The SECOND lib whose loss removes a deny, and the
# one that made this change's original premise ("four faults fall open
# silently") wrong. It backs the DESIGN/PLAN outbound leg, which is gated on
# `command -v phase_step_satisfied` and denies when phase_enforcement.outbound
# is "deny". Measured: with that config and a chain-covered push, removing ONLY
# this lib turns the deny into an allow.
#
# The A/B pair is the proof — without the "present" leg denying, the "removed"
# leg allowing would prove nothing about this lib.
# ---------------------------------------------------------------------------
printf '%s' '{"phase_enforcement":{"outbound":"deny"}}' > "${HOME}/.claude/skill-config.json"
printf '%s' '{"chain":["brainstorming","writing-plans","requesting-code-review","verification-before-completion"],"current_index":3,"completed":["requesting-code-review","verification-before-completion"],"updated_at":"2026-08-12T10:00:00Z"}' \
    > "${HOME}/.claude/.skill-composition-state-${_TOK}"
out_with="$(run)"
assert_equals "phase-evidence leg DENIES while its lib is present" \
    "true" "$(_has_decision "${out_with}")"
rm -f "${_TROOT}/hooks/lib/phase-evidence.sh"
out_without="$(run)"; adv="$(_advisory_text "${out_without}")"
assert_equals   "removing phase-evidence.sh drops that deny" \
    "false" "$(_has_decision "${out_without}")"
assert_contains "advisory names phase-evidence.sh"           "phase-evidence.sh" "${adv:-<empty>}"
assert_contains "advisory distinguishes warn mode from deny mode" \
    "deny" "${adv:-<empty>}"
cp "${PROJECT_ROOT}/hooks/lib/phase-evidence.sh" "${_TROOT}/hooks/lib/phase-evidence.sh"
rm -f "${HOME}/.claude/skill-config.json" "${HOME}/.claude/.skill-composition-state-${_TOK}"

# Drop the seeded evidence again for the deny-direction pins below.
_bl_dir="$(branch_ledger_dir "${PROJECT_ROOT}" 2>/dev/null || true)"
[ -n "${_bl_dir}" ] && [ -d "${_bl_dir}" ] && rm -rf "${_bl_dir}"

# ---------------------------------------------------------------------------
# Cell 6 — verdict.sh absent with NO evidence. The global fail-closed gate
# denies first and exits, so the advisory is deliberately not emitted: the
# guard may put at most one JSON object on stdout, and the user is already
# being stopped. Pinned so the deny is not lost to a future refactor.
# ---------------------------------------------------------------------------
rm -f "${_TROOT}/hooks/lib/verdict.sh"
out="$(run_stable)"
assert_contains "absent verdict lib + no evidence still DENIES" '"deny"' "${out:-<empty>}"
assert_equals   "a deny suppresses the advisory (one JSON object)" "" "$(_advisory_text "${out}")"
_restore_verdict

# ---------------------------------------------------------------------------
# Cell 4 — branch-ledger.sh sources cleanly but defines no functions. This
# DENIES today (the undefined call is used as `cmd && flag=true`, so it is a
# handled failure, not an ERR-trap exit) and it must KEEP denying.
#
# CLAUDE.md's mandated guard form is source + `command -v <fn>` + flag, and
# branch-ledger.sh does not use it. Adding it here would set _LEDGER_OK=false
# and collapse this cell into cell 2 — turning a DENY into an ALLOW. That is a
# real weakening of enforcement, so it is deliberately NOT done: the issue's
# no-regression clause forbids changing any permissionDecision. The deny
# message names the wrong remedy ("no record exists" when the truth is "could
# not check"), which is a separate, non-silent problem.
# ---------------------------------------------------------------------------
: > "${_TROOT}/hooks/lib/branch-ledger.sh"
echo '# sources cleanly, defines nothing' >> "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"
assert_contains "partially-loaded ledger lib still DENIES (must not weaken)" \
    '"deny"' "${out:-<empty>}"
_restore_ledger

# ---------------------------------------------------------------------------
# Cell 3b — branch-ledger.sh runs `false` mid-source. KNOWN NOT COVERED by the
# advisory: the ERR trap fires DURING the source, so the hook exits before any
# accumulator could be read. That shape needs `trap - ERR` around every
# lib-loading region and is tracked as issue #192.
#
# Asserted as EMPTY on purpose, so this is a real pin rather than a sentence:
# it fails the day #192 lands, which is the point — whoever fixes #192 must
# come here and assert the advisory instead.
# ---------------------------------------------------------------------------
printf '\nfalse\n' >> "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"
assert_equals "ERR-trap-exiting lib is still silent (#192 boundary — update when #192 lands)" \
    "" "${out}"
_restore_ledger

# ---------------------------------------------------------------------------
# The advisory must never carry a permissionDecision of its own: a decision on
# the advisory channel would auto-approve the command and suppress every
# downstream warning (documented bug shape in the guard). Asserted TOGETHER
# with the advisory being present — the absence check alone passes when there
# is no advisory at all, which is how a removed feature would sneak through.
# ---------------------------------------------------------------------------
rm -f "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(run_stable)"; adv="$(_advisory_text "${out}")"
assert_contains "advisory is present to be judged"              "GATE DEGRADED" "${adv:-<empty>}"
assert_equals   "degradation advisory carries no permissionDecision" \
    "false" "$(_has_decision "${out}")"
_restore_ledger

print_summary
