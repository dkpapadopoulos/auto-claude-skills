#!/usr/bin/env bash
# Item 2 (openspec: remedy-aware-backbone): a deny must never demand a remedy the
# install cannot execute. Pre-fix, a REVIEW/VERIFY deny told a no-superpowers
# install to "invoke Skill(superpowers:X)" — impossible. The fix keeps the DENY
# (the gate is never suppressed by a skill-availability signal — that would hand
# an agent a deny->allow lever, the exact thing this gate exists to prevent) and
# instead APPENDS an achievable remedy ("run /setup") to the message when the
# demanded skill is genuinely absent ON DISK.
#
# SECURITY (2026-08-28 review): availability is resolved from DISK presence of
# the skill's SKILL.md, never the registry cache (a plain 0644 file any Bash turn
# can overwrite). Because availability only changes MESSAGE WORDING and never the
# decision, even deleting the plugin cannot turn a deny into an allow. Two
# assertions pin that: a tampered cache is inert, and a `gh pr merge` with the
# backbone absent still DENIES (not silently allowed).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-backbone-advisory.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pg-bb-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
_PLUGINS="$HOME/.claude/plugins/cache/mkt/superpowers/6.3.0/skills"
_PVHEAD="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"

_write_verdict() { jq -nc --arg s "${_PVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "$HOME/.claude/.skill-project-verified-${_TOK}"; }
_rm_verdict()    { rm -f "$HOME/.claude/.skill-project-verified-${_TOK}"; }
_install()       { local n; for n in "$@"; do mkdir -p "${_PLUGINS}/${n}"; printf -- '---\n' > "${_PLUGINS}/${n}/SKILL.md"; done; }
_uninstall_all() { rm -rf "$HOME/.claude/plugins"; }
run_guard() { jq -n --arg tp "$_TPATH" --arg cmd "${1:-git push origin HEAD}" '{"transcript_path":$tp,"tool_input":{"command":$cmd}}' | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PUSH_GATE_CAPTURE_DISABLE=1 bash "${GUARD}" 2>/dev/null; }

# (1) Backbone NOT installed: the push is STILL denied, but the message carries
#     the achievable /setup remedy (not the impossible "invoke Skill(superpowers)").
_uninstall_all; _write_verdict
out="$(run_guard)"
assert_contains "uninstalled backbone still denies"        '"deny"' "${out:-<empty>}"
assert_contains "deny message offers the achievable /setup" '/setup' "${out:-}"

# (2) Backbone installed but unrun: deny with the normal remedy, NO /setup hint.
_install requesting-code-review verification-before-completion
out="$(run_guard)"
assert_contains     "installed-but-unrun backbone denies" '"deny"'  "${out:-<empty>}"
assert_not_contains "installed remedy is not the /setup hint" '/setup' "${out:-}"

# (3) SECURITY: a tampered cache claiming available:false is INERT while the
#     skill is on disk -> deny fires, and the message is NOT the /setup wording
#     (disk is authority, cache ignored). Proves no cache-forge deny->allow lever.
jq -nc '{version:"4.0.0",skills:[
    {name:"requesting-code-review",available:false,enabled:true},
    {name:"verification-before-completion",available:false,enabled:true}]}' \
    > "$HOME/.claude/.skill-registry-cache.json"
out="$(run_guard)"
assert_contains     "forged cache cannot disable the gate" '"deny"' "${out:-<empty>}"
assert_not_contains "forged cache cannot even change wording" '/setup' "${out:-}"
rm -f "$HOME/.claude/.skill-registry-cache.json"

# (4) Partial: verify installed+unrun, review uninstalled -> still denies.
_uninstall_all; _install verification-before-completion; _rm_verdict
out="$(run_guard)"
assert_contains "partial-install still denies" '"deny"' "${out:-<empty>}"

# (5) SECURITY/merge: a `gh pr merge` with the backbone uninstalled must DENY
#     (never silently allow). Deny is action-independent, so no merge-silence gap.
_uninstall_all; _rm_verdict
out="$(run_guard 'gh pr merge 42 --squash')"
assert_contains "merge with uninstalled backbone still denies" '"deny"' "${out:-<empty>}"

export HOME="$_OLDHOME"
print_summary
exit $?
