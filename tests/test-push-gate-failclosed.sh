#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-failclosed.sh ==="

# The global fail-closed gate closes the pre-existing fail-open hole: a git push
# with NO active composition state used to be allowed unconditionally. Now every
# push requires a durable review record AND a passing verification signal for the
# branch, unless explicitly bypassed. Two invariants are equally load-bearing and
# both tested here:
#   - The bypass is HUMAN-ONLY: only a human-set env var or a terminal push skips
#     the gate. The command string is NOT scanned for the token, because the agent
#     composes it — an inline scan would be an agent-forgeable bypass.
#   - Fail-open on INFRASTRUCTURE error is preserved: with no jq, every evidence
#     leg is unsatisfiable, so the gate must fall OPEN (never deny), matching the
#     "jq optional at runtime" invariant.

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# --- Content assertions (wiring) ---
g="$(cat "${GUARD}")"
assert_contains     "gate is fail-closed"                    "fail-closed"             "${g}"
assert_contains     "gate honors ACSM_SKIP_PUSH_GATE"        "ACSM_SKIP_PUSH_GATE"     "${g}"
# Lock in the human-only decision: the hook must NOT scan the command string for
# the bypass token (that path was agent-forgeable and was deliberately removed).
assert_not_contains "no agent-forgeable inline bypass scan"  'in *ACSM_SKIP_PUSH_GATE' "${g}"

# --- Behavioral setup (mirrors test-push-gate-ledger.sh) ---
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pg-fc-home-XXXXXX)"
mkdir -p "$HOME/.claude"

_TPATH="$HOME/t.jsonl"
touch "$_TPATH"               # basename "t" -> token "session-t"
_TOK="session-t"
_COMP="$HOME/.claude/.skill-composition-state-${_TOK}"

# CRITICAL: no composition state file exists (the fail-open hole). Provide a clean
# verdict covering HEAD so (a) the routing-governance gate is satisfied and (b) the
# VERIFY leg is met — isolating the REVIEW leg as the sole reason for any denial.
_PVHEAD="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
_VERDICT="$HOME/.claude/.skill-project-verified-${_TOK}"
_write_verdict() { jq -nc --arg s "${_PVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${_VERDICT}"; }
_write_verdict

_mkinput() {
    local cmd="${1:-git push origin HEAD}"
    jq -n --arg tp "$_TPATH" --arg cmd "$cmd" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}
run_guard() { _mkinput "${1:-}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null; }

# (a) No composition, no ledger, verify satisfied but REVIEW missing -> DENY.
#     Under the old fail-open behavior this push was allowed (no _COMP file).
[ -f "${_COMP}" ] && rm -f "${_COMP}"
out="$(run_guard)"
assert_contains     "no composition + no review record => deny" '"deny"'                    "${out:-<empty>}"
assert_contains     "deny names the missing review gate"        "requesting-code-review"    "${out:-<empty>}"

# (b) Record the review milestone in the durable ledger -> ALLOW (both legs met).
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
branch_ledger_record "requesting-code-review" "${PROJECT_ROOT}"
out="$(run_guard)"
assert_not_contains "review recorded + clean verdict => no deny" '"deny"' "${out:-}"

# (c) Isolate the VERIFY leg: review is recorded, but remove the clean verdict so
#     the verify leg is unmet -> DENY naming verification-before-completion.
rm -f "${_VERDICT}"
out="$(run_guard)"
assert_contains     "review present + verify missing => deny"          '"deny"'                        "${out:-<empty>}"
assert_contains     "deny names the missing verify gate"               "verification-before-completion" "${out:-<empty>}"

# (d) The inline command-string prefix is NOT an escape hatch (agent-forgeable) ->
#     still DENY. Same state as (c): review recorded, verify missing.
out="$(run_guard "ACSM_SKIP_PUSH_GATE=1 git push origin HEAD")"
assert_contains     "inline ACSM_SKIP_PUSH_GATE=1 does NOT bypass gate" '"deny"' "${out:-<empty>}"

# (e) Escape hatch via HUMAN-set exported env var -> ALLOW.
out="$(_mkinput | ACSM_SKIP_PUSH_GATE=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null)"
assert_not_contains "exported ACSM_SKIP_PUSH_GATE=1 bypasses gate" '"deny"' "${out:-}"

# (f) Non-push commands are never gated (fast-path unchanged).
out="$(_mkinput "git status" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null)"
assert_not_contains "git status is not gated" '"deny"' "${out:-}"

# (g) Fail-open on missing jq. Every evidence leg is jq-dependent (the ledger's
#     sole writer exits early without jq, the .completed fallback is jq-guarded,
#     and the verdict lib returns non-clean without jq), so with no jq NO record is
#     establishable and the gate MUST fall open. Same state as (c)/(d) — which
#     denies WITH jq — so a non-deny here proves the jq guard, not an empty state.
#     Build a PATH mirroring the real one minus jq; resolve the token via the
#     singleton file (the no-jq command-extraction fallback leaves transcript empty).
printf '%s' "${_TOK}" > "$HOME/.claude/.skill-session-token"
NOJQ_BIN="$(mktemp -d /tmp/pg-fc-nojq-XXXXXX)"
_oIFS="$IFS"; IFS=:
for _d in $PATH; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
        [ -e "$_f" ] || continue
        _b="$(basename "$_f")"
        [ "$_b" = "jq" ] && continue
        [ -e "$NOJQ_BIN/$_b" ] && continue
        [ -x "$_f" ] && ln -s "$_f" "$NOJQ_BIN/$_b" 2>/dev/null
    done
done
IFS="$_oIFS"
if command -v git >/dev/null 2>&1 && [ -e "$NOJQ_BIN/git" ] && [ ! -e "$NOJQ_BIN/jq" ]; then
    out="$(_mkinput | PATH="$NOJQ_BIN" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null)"
    assert_not_contains "no jq => gate falls open (no deny)" '"deny"' "${out:-}"
else
    echo "  SKIP: could not build a jq-less PATH for the fail-open test"
fi
rm -rf "$NOJQ_BIN"

export HOME="$_OLDHOME"
print_summary
exit $?
