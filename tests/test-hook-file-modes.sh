#!/usr/bin/env bash
# test-hook-file-modes.sh — every script hooks/hooks.json runs directly must be executable,
# in the git index (what ships) and on disk (what this checkout runs).
#
# The harness executes a hook's `command` as-is, so a 100644 file fails with "permission
# denied" and the hook silently never runs. That happened twice (2026-09-16):
# hooks/outbound-consent-hook.sh shipped as 100644 in #253 — the advisory egress observer
# never ran in any install — and egress-consent-ask-hook.sh was committed 100644 when its
# chmod was lost. Tests that invoke hooks via `/bin/bash <file>` cannot see this.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-hook-file-modes.sh ==="

HJ="${PROJECT_ROOT}/hooks/hooks.json"
if ! command -v jq >/dev/null 2>&1; then
    _record_fail "jq available" "jq is required to read hooks.json"
    print_summary
    exit 1
fi

# Commands of the form "${CLAUDE_PLUGIN_ROOT}/<path>[ args]" — the file is the first word.
PATHS="$(jq -r '.. | objects | .command? // empty' "${HJ}" \
    | sed -n 's|^\${CLAUDE_PLUGIN_ROOT}/\([^ ]*\).*|\1|p' | sort -u)"
count=0
while IFS= read -r rel; do
    [ -n "${rel}" ] || continue
    count=$((count + 1))
    mode="$(git -C "${PROJECT_ROOT}" ls-files -s -- "${rel}" 2>/dev/null | awk '{print $1}')"
    if [ -z "${mode}" ]; then
        _record_fail "${rel}: tracked by git" "not in the index"
    elif [ "${mode}" = "100755" ]; then
        _record_pass "${rel}: executable in git (100755)"
    else
        _record_fail "${rel}: executable in git" "index mode ${mode}"
    fi
    if [ -x "${PROJECT_ROOT}/${rel}" ]; then
        _record_pass "${rel}: executable on disk"
    else
        _record_fail "${rel}: executable on disk" "not executable"
    fi
done <<EOF
${PATHS}
EOF

# Floor: a parse that silently matched nothing must not read as "all executable".
if [ "${count}" -ge 10 ]; then
    _record_pass "hooks.json yielded ${count} script paths"
else
    _record_fail "hooks.json yielded enough script paths" "only ${count}"
fi

print_summary
