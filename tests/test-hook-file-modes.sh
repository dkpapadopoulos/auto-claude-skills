#!/usr/bin/env bash
# test-hook-file-modes.sh — every script hooks/hooks.json runs directly must be executable,
# in the git index (what ships) and on disk (what this checkout runs).
#
# The harness executes a hook's `command` as-is, so a 100644 file fails with "permission
# denied" and the hook silently never runs. That happened twice (2026-09-16):
# hooks/outbound-consent-hook.sh shipped as 100644 in #253 — the advisory egress observer
# never ran in any install — and egress-consent-ask-hook.sh was committed 100644 when its
# chmod was lost. Tests that invoke hooks via `/bin/bash <file>` cannot see this.
#
# EVERY command is accounted for: a form this test does not recognise is a failure, never
# a silent skip (a quoted path used to be skipped while the floor still passed).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-hook-file-modes.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    _record_fail "jq available" "jq is required to read hooks.json"
    print_summary
    exit 1
fi

# extract <hooks.json> — one line per command: "path<TAB><rel>" for a recognised
# ${CLAUDE_PLUGIN_ROOT}/<rel> command (optionally quoted), else "unknown<TAB><command>".
extract() {
    jq -r '.. | objects | .command? // empty | strings' "$1" | while IFS= read -r cmd; do
        rel="$(printf '%s\n' "${cmd}" \
            | sed -n -E 's|^["'"'"']?\$\{CLAUDE_PLUGIN_ROOT\}/([^ "'"'"']+)["'"'"']?( .*)?$|\1|p')"
        if [ -n "${rel}" ]; then
            printf 'path\t%s\n' "${rel}"
        else
            printf 'unknown\t%s\n' "${cmd}"
        fi
    done
}

# Self-check of the extractor on a synthetic file, so it cannot silently match nothing.
SYN="$(mktemp "${TMPDIR:-/tmp}/hookmodes.XXXXXX")"
trap 'rm -f "${SYN}"' EXIT
cat > "${SYN}" <<'JSON'
{"hooks":{"A":[{"hooks":[
  {"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/a.sh"},
  {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/hooks/b.sh\" --flag"},
  {"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/c.sh guard --daemon"},
  {"type":"command","command":"node something.js"}
]}]}}
JSON
assert_equals "extractor: bare, quoted and argument forms are all recognised; others are unknown" \
    "path:hooks/a.sh path:hooks/b.sh path:hooks/c.sh unknown:node something.js" \
    "$(extract "${SYN}" | awk -F'\t' '{printf "%s%s:%s", (NR>1?" ":""), $1, $2}')"

count=0
unknown=0
while IFS="$(printf '\t')" read -r kind rel; do
    [ -n "${kind}" ] || continue
    if [ "${kind}" = "unknown" ]; then
        unknown=$((unknown + 1))
        _record_fail "hooks.json command in a recognised form" "${rel}"
        continue
    fi
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
$(extract "${PROJECT_ROOT}/hooks/hooks.json" | sort -u)
EOF

if [ "${count}" -ge 10 ]; then
    _record_pass "hooks.json yielded ${count} script paths (${unknown} unrecognised)"
else
    _record_fail "hooks.json yielded enough script paths" "only ${count}"
fi

print_summary
