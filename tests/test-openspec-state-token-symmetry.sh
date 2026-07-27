#!/usr/bin/env bash
# test-openspec-state-token-symmetry.sh — issue #157.
#
# Every instruction in this repo that tells the model to WRITE
# ~/.claude/.skill-openspec-state-<token> from a Bash turn must resolve the
# token own-session-first, because the READER (the PLAN-phase design guard and
# the intent read-back in hooks/skill-activation-hook.sh) resolves payload-first
# per issue #51. ~/.claude/.skill-session-token is a shared last-writer-wins
# singleton: under concurrent sessions it names a DIFFERENT conversation, so a
# singleton-resolved write scatters into a file the reader never opens and the
# DESIGN->PLAN completeness hint silently never fires.
#
# These writers live in prose/config (SKILL.md bodies, methodology-hint text,
# an injected directive), so nothing but a content assert stops them from
# regressing. All assertions here are red against the pre-#157 files.
#
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-openspec-state-token-symmetry.sh ==="

# Each writer surface: <label>|<path>|<lib-assert>
# lib-assert=yes only where naming the lib is NOT trivially true: the two hook
# files already reference hooks/lib/session-token.sh for their own token
# resolution (and the drift-canary manifest), so that assert would pass on the
# pre-#157 tree and prove nothing. Honest accounting: for those two, the
# resolver-name assert is the load-bearing one.
WRITERS="product-discovery SKILL|skills/product-discovery/SKILL.md|yes
openspec-ship SKILL|skills/openspec-ship/SKILL.md|yes
default-triggers hints|config/default-triggers.json|yes
fallback-registry hints|config/fallback-registry.json|yes
spec-driven PERSIST DESIGN|hooks/session-start-hook.sh|no
intent-extraction directive|hooks/skill-activation-hook.sh|no"

# --- 1. Every writer surface names the shared resolver ---
OLD_IFS="$IFS"
IFS='
'
for entry in ${WRITERS}; do
    IFS="$OLD_IFS"
    label="${entry%%|*}"
    rest="${entry#*|}"
    rel="${rest%%|*}"
    want_lib="${rest##*|}"
    content="$(cat "${PROJECT_ROOT}/${rel}" 2>/dev/null)"

    assert_contains "${label}: calls resolve_own_session_token" \
        "resolve_own_session_token" "${content}"
    # Must SOURCE the lib that owns the `session-<id>` format rather than
    # re-deriving the shape locally (the #156 single-sourcing contract).
    if [ "${want_lib}" = "yes" ]; then
        assert_contains "${label}: sources hooks/lib/session-token.sh" \
            "hooks/lib/session-token.sh" "${content}"
    fi
    IFS='
'
done
IFS="$OLD_IFS"

# --- 2. The singleton survives ONLY as the last-resort fallback ---
# The fallback form is `... || cat ~/.claude/.skill-session-token`. A primary
# read is an assignment straight from the file: `TOKEN=$(cat ~/...)` in any
# quoting style. grep -E, not a substring match, because the legitimate
# fallback line names the same path.
check_no_primary_singleton_read() {
    local label="$1" rel="$2" hit="absent"
    grep -Eq 'TOKEN=[^|]*(\$\(|`)[[:space:]]*cat[[:space:]]+~?/?[^|]*\.skill-session-token' \
        "${PROJECT_ROOT}/${rel}" && hit="present"
    assert_equals "${label}: no primary singleton read (fallback only)" "absent" "${hit}"
}
check_no_primary_singleton_read "product-discovery SKILL" "skills/product-discovery/SKILL.md"
check_no_primary_singleton_read "openspec-ship SKILL"     "skills/openspec-ship/SKILL.md"

# --- 3. No prose telling the model to read the singleton for the token ---
for rel in skills/product-discovery/SKILL.md skills/openspec-ship/SKILL.md; do
    content="$(cat "${PROJECT_ROOT}/${rel}" 2>/dev/null)"
    assert_not_contains "${rel}: no 'Read the singleton' instruction" \
        'Read `~/.claude/.skill-session-token`' "${content}"
done

# --- 4. Shell state does not persist across Bash tool calls ---
# Each executable block that calls an openspec_state_* helper must resolve the
# token itself; a block relying on a $TOKEN set by an earlier tool call writes
# nothing (every helper returns silently on an empty token). Pin the warning so
# a future DRY refactor cannot quietly reintroduce the cross-call dependency.
for rel in skills/product-discovery/SKILL.md skills/openspec-ship/SKILL.md; do
    content="$(cat "${PROJECT_ROOT}/${rel}" 2>/dev/null)"
    assert_contains "${rel}: warns shell state does not persist between calls" \
        "does not persist between" "${content}"
done

# --- 5. Helper contract the assertions above depend on ---
# If openspec_state_* ever started writing under an empty token, an unresolved
# token would become a wrong-file write instead of a silent no-op, and the
# reasoning in this file would need revisiting.
STATE_LIB="${PROJECT_ROOT}/hooks/lib/openspec-state.sh"
assert_file_exists "openspec-state.sh exists" "${STATE_LIB}"
STATE_CONTENT="$(cat "${STATE_LIB}" 2>/dev/null)"
assert_contains "openspec-state helpers no-op on an empty token" \
    'z "$token"' "${STATE_CONTENT}"

print_summary
exit $?
