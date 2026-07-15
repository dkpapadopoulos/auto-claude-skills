#!/usr/bin/env bash
# test-plugin-drift-canary.sh — installed-plugin drift canary (post-audit
# triage item 1, Codex D2 minimal). When a session's cwd IS the plugin source
# repo but the plugin runs from the versioned cache, stale cache silently
# enforces old gate logic. The canary must surface version drift and
# gate-enforcement file drift, stay silent otherwise, and fail open.
# Behavioral: runs the REAL hook in a disposable plugin root ("cache") plus a
# disposable source repo, steering cwd via the hook payload's .cwd field.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-plugin-drift-canary.sh ==="

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pdc-home-XXXXXX)"
mkdir -p "$HOME/.claude"

# Disposable "cache" plugin root and disposable "source repo", initially identical.
_TROOT="$(mktemp -d /tmp/pdc-cache-XXXXXX)"
_SRC="$(mktemp -d /tmp/pdc-src-XXXXXX)"
for _d in "${_TROOT}" "${_SRC}"; do
    cp -R "${PROJECT_ROOT}/hooks" "${_d}/hooks"
    cp -R "${PROJECT_ROOT}/config" "${_d}/config"
    mkdir -p "${_d}/.claude-plugin"
    printf '{"name":"auto-claude-skills","version":"3.71.0"}\n' \
        > "${_d}/.claude-plugin/plugin.json"
done

_run_hook() {  # $1 = cwd reported in the hook payload
    printf '{"cwd":"%s"}' "$1" | CLAUDE_PLUGIN_ROOT="${_TROOT}" \
        bash "${_TROOT}/hooks/session-start-hook.sh" 2>/dev/null
}

# (a) cwd is NOT a plugin source repo => silent.
_PLAIN="$(mktemp -d /tmp/pdc-plain-XXXXXX)"
out="$(_run_hook "${_PLAIN}")"
assert_contains     "non-source cwd still emits session context" "SessionStart" "${out:-<empty>}"
assert_not_contains "non-source cwd emits no drift canary" "PLUGIN DRIFT CANARY" "${out:-}"
rm -rf "${_PLAIN}"

# (b) source repo, same version, identical gate files => silent.
out="$(_run_hook "${_SRC}")"
assert_not_contains "healthy source-repo session emits no drift canary" "PLUGIN DRIFT CANARY" "${out:-}"

# (c) version mismatch => warning names both versions.
printf '{"name":"auto-claude-skills","version":"3.72.0"}\n' \
    > "${_SRC}/.claude-plugin/plugin.json"
out="$(_run_hook "${_SRC}")"
assert_contains "version drift => canary emitted"    "PLUGIN DRIFT CANARY" "${out:-<empty>}"
assert_contains "canary names the running version"   "3.71.0" "${out:-<empty>}"
assert_contains "canary names the source version"    "3.72.0" "${out:-<empty>}"
# Restore matching version.
printf '{"name":"auto-claude-skills","version":"3.71.0"}\n' \
    > "${_SRC}/.claude-plugin/plugin.json"

# (d) same version, gate-enforcement file drifted in source => canary names it.
printf '\n# drift\n' >> "${_SRC}/hooks/lib/verdict.sh"
out="$(_run_hook "${_SRC}")"
assert_contains "gate-file drift => canary emitted"  "PLUGIN DRIFT CANARY" "${out:-<empty>}"
assert_contains "canary names the drifted file"      "verdict.sh" "${out:-<empty>}"
cp "${PROJECT_ROOT}/hooks/lib/verdict.sh" "${_SRC}/hooks/lib/verdict.sh"

# (e) different plugin name in cwd manifest => not OUR source repo => silent.
printf '{"name":"some-other-plugin","version":"9.9.9"}\n' \
    > "${_SRC}/.claude-plugin/plugin.json"
out="$(_run_hook "${_SRC}")"
assert_not_contains "foreign plugin repo emits no drift canary" "PLUGIN DRIFT CANARY" "${out:-}"
printf '{"name":"auto-claude-skills","version":"3.71.0"}\n' \
    > "${_SRC}/.claude-plugin/plugin.json"

# (f) fail-open: running plugin root has no manifest => silent, hook intact.
rm -f "${_TROOT}/.claude-plugin/plugin.json"
out="$(_run_hook "${_SRC}")"
assert_contains     "manifest-less hook still emits session context" "SessionStart" "${out:-<empty>}"
assert_not_contains "manifest-less run emits no drift canary" "PLUGIN DRIFT CANARY" "${out:-}"

rm -rf "${_TROOT}" "${_SRC}"
export HOME="$_OLDHOME"
print_summary
exit $?
