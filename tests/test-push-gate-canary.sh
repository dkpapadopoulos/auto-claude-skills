#!/usr/bin/env bash
# test-push-gate-canary.sh — session-start canary for push-gate preconditions
# (audit F5). The gate is deliberately fail-open on infra error (missing jq,
# unsourceable gate lib); that degradation must be VISIBLE at session start,
# and a healthy environment must stay silent. Behavioral: runs the REAL hook
# in a disposable plugin root.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-canary.sh ==="

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgc-home-XXXXXX)"
mkdir -p "$HOME/.claude"

# Disposable plugin root: only what session-start needs.
_TROOT="$(mktemp -d /tmp/pgc-root-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks" "${_TROOT}/hooks"
cp -R "${PROJECT_ROOT}/config" "${_TROOT}/config"
# scripts/ too: the canary parse-checks scripts/memory-leak-check.sh (#187),
# so a root without it is not a HEALTHY root — cell (a) would fail for the
# fixture's incompleteness rather than for anything the hook did. Copy the
# whole directory so the next canary addition under scripts/ needs no edit
# here.
cp -R "${PROJECT_ROOT}/scripts" "${_TROOT}/scripts"

_run_hook() {
    printf '{}' | CLAUDE_PLUGIN_ROOT="${_TROOT}" \
        bash "${_TROOT}/hooks/session-start-hook.sh" 2>/dev/null
}

# (a) Healthy plugin root => NO canary noise.
out="$(_run_hook)"
assert_contains     "healthy hook still emits session context" "SessionStart" "${out:-<empty>}"
assert_not_contains "healthy environment emits no canary"      "PUSH-GATE CANARY" "${out:-}"

# (b) Syntax-broken gate lib => canary names it. The injected line is the
#     documented Bash-3.2 killer (quoted operand in arithmetic), which is
#     exactly the class that silently killed session-start in PR #47.
printf '\nX=$(( "1" / 1 ))\n' >> "${_TROOT}/hooks/lib/branch-ledger.sh"
out="$(_run_hook)"
assert_contains "broken lib => canary emitted"        "PUSH-GATE CANARY"  "${out:-<empty>}"
assert_contains "canary names the broken component"   "branch-ledger.sh"  "${out:-<empty>}"

# Restore for the next case.
cp "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh" "${_TROOT}/hooks/lib/branch-ledger.sh"

# (c) Missing gate lib => canary names it.
rm -f "${_TROOT}/hooks/lib/verdict.sh"
out="$(_run_hook)"
assert_contains "missing lib => canary emitted"       "PUSH-GATE CANARY"  "${out:-<empty>}"
assert_contains "canary names the missing component"  "verdict.sh"        "${out:-<empty>}"
cp "${PROJECT_ROOT}/hooks/lib/verdict.sh" "${_TROOT}/hooks/lib/verdict.sh"

# (c2) Unparseable leak-detection engine => canary names it. publish-guard.sh
#      was covered before #187 and the engine it actually calls was not, so a
#      stale or broken engine in the versioned plugin cache passed silently.
#      Injected fault matches cells (e)/(f): the engine is EXECUTED, not
#      sourced, so it is parse-checked only and — like publish-guard.sh — this
#      cannot catch the Bash-3.2 quoted-arithmetic killer that cell (b) uses
#      against a source-probed lib. Measured: that line leaves `bash -n` clean.
printf 'if [ \n' > "${_TROOT}/scripts/memory-leak-check.sh"
out="$(_run_hook)"
assert_contains "unparseable leak engine trips the canary" "memory-leak-check.sh (unparseable)" "${out:-<empty>}"
cp "${PROJECT_ROOT}/scripts/memory-leak-check.sh" "${_TROOT}/scripts/memory-leak-check.sh"

# (c3) Missing leak-detection engine => canary names it.
rm -f "${_TROOT}/scripts/memory-leak-check.sh"
out="$(_run_hook)"
assert_contains "missing leak engine trips the canary" "memory-leak-check.sh (missing)" "${out:-<empty>}"
cp "${PROJECT_ROOT}/scripts/memory-leak-check.sh" "${_TROOT}/scripts/memory-leak-check.sh"

# (d) jq-less PATH => the fallback message states the gate falls open.
NOJQ_BIN="$(mktemp -d /tmp/pgc-nojq-XXXXXX)"
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
if [ -e "$NOJQ_BIN/bash" ] && [ ! -e "$NOJQ_BIN/jq" ]; then
    out="$(printf '{}' | PATH="$NOJQ_BIN" CLAUDE_PLUGIN_ROOT="${_TROOT}" \
        bash "${_TROOT}/hooks/session-start-hook.sh" 2>/dev/null)"
    assert_contains "jq-less fallback names the gate consequence" \
        "push gate" "${out:-<empty>}"
    assert_contains "jq-less fallback says it falls open" \
        "falls open" "${out:-<empty>}"
else
    echo "  SKIP: could not build a jq-less PATH"
fi
rm -rf "$NOJQ_BIN"

# (e) Missing publish-guard.sh (#174 leak gate) => canary names it.
rm -f "${_TROOT}/hooks/publish-guard.sh"
out="$(_run_hook)"
assert_contains "missing publish-guard.sh trips the canary" "publish-guard.sh (missing)" "${out:-<empty>}"
cp "${PROJECT_ROOT}/hooks/publish-guard.sh" "${_TROOT}/hooks/publish-guard.sh"

# (f) Unparseable publish-guard.sh => canary names it.
printf 'if [ \n' > "${_TROOT}/hooks/publish-guard.sh"
out="$(_run_hook)"
assert_contains "unparseable publish-guard.sh trips the canary" "publish-guard.sh (unparseable)" "${out:-<empty>}"
cp "${PROJECT_ROOT}/hooks/publish-guard.sh" "${_TROOT}/hooks/publish-guard.sh"

rm -rf "${_TROOT}"
export HOME="$_OLDHOME"
print_summary
exit $?
