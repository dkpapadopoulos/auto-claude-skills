#!/usr/bin/env bash
# test-consult-dispatch.sh — scripts/consult-dispatch.sh is the only sender panel and
# second-opinion may use for cross-family content, and it must refuse without the user's
# approval of that exact package.
#
# Receipts are minted by running the REAL ask + receipt hooks on payloads shaped like the
# 2026-09-16 live capture, so this exercises the chain end to end. codex and gitleaks are
# PATH stubs (no env-var override exists in the script, by design: an override that
# changes which binary runs or skips the scan would itself be a bypass).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-consult-dispatch.sh ==="

DISPATCH="${PROJECT_ROOT}/scripts/consult-dispatch.sh"
ASK_HOOK="${PROJECT_ROOT}/hooks/egress-consent-ask-hook.sh"
RCPT_HOOK="${PROJECT_ROOT}/hooks/egress-consent-receipt-hook.sh"
assert_file_exists "consult-dispatch.sh exists" "${DISPATCH}"

T="$(mktemp -d "${TMPDIR:-/tmp}/consult-dispatch.XXXXXX")" || exit 1
trap 'rm -rf "${T}"' EXIT
H="${T}/home"; mkdir -p "${H}/.claude/projects/p"
SID="conv-D"; TOK="session-${SID}"
TP="${H}/.claude/projects/p/${SID}.jsonl"; : > "${TP}"
printf 'session-FOREIGN' > "${H}/.claude/.skill-session-token"

# --- PATH construction --------------------------------------------------------------
TOOLS="${T}/tools"; mkdir -p "${TOOLS}"
for tool in bash sh cat mv rm cp date basename dirname shasum sha256sum perl sed tr cut \
            mkdir chmod stat find head tail wc env mktemp cmp grep printf ln ls rmdir sleep; do
    src="$(command -v "${tool}" 2>/dev/null)"; [ -n "${src}" ] && [ -x "${src}" ] && ln -sf "${src}" "${TOOLS}/${tool}"
done
JQD="${T}/jqd"; mkdir -p "${JQD}"; ln -sf "$(command -v jq)" "${JQD}/jq"
STUBS="${T}/stubs"; mkdir -p "${STUBS}"
REC="${T}/codex-calls"; mkdir -p "${REC}"
cat > "${STUBS}/codex" <<EOF
#!/bin/bash
n=\$(ls "${REC}" | wc -l | tr -d ' '); n=\$((n + 1)); d="${REC}/\${n}"; mkdir -p "\$d"
printf '%s\n' "\$@" > "\$d/argv"; cat > "\$d/stdin"; pwd > "\$d/cwd"
out=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
[ -f "${T}/codex.rc" ] && exit "\$(cat "${T}/codex.rc")"
[ -n "\$out" ] && printf 'OK from stub\n' > "\$out"
exit 0
EOF
cat > "${STUBS}/gitleaks" <<EOF
#!/bin/bash
cat > /dev/null
exit "\$(cat "${T}/gitleaks.rc" 2>/dev/null || echo 0)"
EOF
chmod +x "${STUBS}/codex" "${STUBS}/gitleaks"
NOGL="${T}/nogl"; mkdir -p "${NOGL}"; ln -sf "${STUBS}/codex" "${NOGL}/codex"
P_FULL="${STUBS}:${JQD}:${TOOLS}"
P_NOGITLEAKS="${NOGL}:${JQD}:${TOOLS}"
P_NOJQ="${STUBS}:${TOOLS}"

calls() { ls "${REC}" | wc -l | tr -d ' '; }
dispatch() { # $1 PATH, $2 session id ("-" = unset), rest = args. Prints "<stdout+stderr>" and sets RC.
    local _p="$1" _s="$2"; shift 2
    if [ "${_s}" = "-" ]; then
        OUT="$(cd "${T}" && env -u CLAUDE_CODE_SESSION_ID PATH="${_p}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            /bin/bash "${DISPATCH}" "$@" 2>&1 < /dev/null)"; RC=$?
    else
        OUT="$(cd "${T}" && env PATH="${_p}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" CLAUDE_CODE_SESSION_ID="${_s}" \
            /bin/bash "${DISPATCH}" "$@" 2>&1 < /dev/null)"; RC=$?
    fi
}
hook() { printf '%s' "$2" | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$1" >/dev/null 2>&1; }
# approve <digest> <package text> <tool_use_id> [label] — the real Pre + Post hooks.
approve() {
    local _q="Send to Codex? [egress-consent:$1]" _label="${4:-Approve and send}" _pre _post _ann='{}'
    _pre="$(jq -nc --arg id "$3" --arg tp "${TP}" --arg q "${_q}" --arg p "$2" \
        '{transcript_path:$tp, tool_use_id:$id, agent_id:null, hook_event_name:"PreToolUse",
          tool_name:"AskUserQuestion",
          tool_input:{questions:[{question:$q, header:"Egress", multiSelect:false,
            options:[{label:"Approve and send", description:"send", preview:$p},
                     {label:"Do not send", description:"keep"}]}]}}')"
    hook "${ASK_HOOK}" "${_pre}"
    [ "${_label}" = "Approve and send" ] && _ann="$(jq -nc --arg q "${_q}" --arg p "$2" '{($q):{preview:$p}}')"
    _post="$(printf '%s' "${_pre}" | jq -c --arg q "${_q}" --arg l "${_label}" --argjson a "${_ann}" \
        '.hook_event_name="PostToolUse" | .tool_input.answers={($q):$l} | .tool_input.annotations=$a
         | .tool_response={questions:.tool_input.questions, answers:{($q):$l}, annotations:$a}')"
    hook "${RCPT_HOOK}" "${_post}"
}
reset() { rm -f "${H}"/.claude/.skill-egress-* "${T}/codex.rc" "${T}/gitleaks.rc" "${H}/.claude/skill-config.json"; rm -rf "${REC:?}"/*; }

PKGF="${T}/package.md"
printf 'Question: is this plan sound?\nRead-only: do not modify files.\n\n' > "${PKGF}"
PKG="$(cat "${PKGF}")"

echo "-- prepare --"
reset
dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
assert_equals "prepare succeeds" "0" "${RC}"
D="$(printf '%s' "${OUT}" | sed -n 's/^digest: \([0-9a-f]\{64\}\)$/\1/p' | head -1)"
assert_equals "prepare prints the canonical digest" "$(printf '%s' "${PKG}" | shasum -a 256 | cut -d' ' -f1)" "${D}"
assert_contains "prepare prints the marker to use" "[egress-consent:${D}]" "${OUT}"
assert_contains "prepare names the approve label" "Approve and send" "${OUT}"
assert_contains "prepare prints the send command" "consult-dispatch.sh\" send ${D}" "${OUT}"
assert_equals "prepare freezes the package owner-only" "600" \
    "$(stat -f '%Lp' "${H}/.claude/.skill-egress-pkg-${TOK}.${D}" 2>/dev/null)"
dispatch "${P_FULL}" "${SID}" prepare gemini "${PKGF}"
assert_equals "unsupported provider -> 2" "2" "${RC}"
dispatch "${P_FULL}" "${SID}" prepare codex "${T}/nope"
assert_equals "missing package -> 2" "2" "${RC}"
: > "${T}/empty.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/empty.md"
assert_equals "empty package -> 2" "2" "${RC}"
printf 'a\000b' > "${T}/nul.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/nul.md"
assert_equals "NUL bytes in package -> 2" "2" "${RC}"
dispatch "${P_FULL}" - prepare codex "${PKGF}"
assert_equals "prepare without own session identity -> 3 (singleton not borrowed)" "3" "${RC}"

echo "-- send: the approved path --"
reset
dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_s1
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "approved send -> 0" "0" "${RC}"
assert_equals "codex invoked exactly once" "1" "$(calls)"
argv="$(cat "${REC}/1/argv" 2>/dev/null)"
assert_contains "codex exec subcommand" "exec" "${argv}"
assert_contains "read-only sandbox requested" "$(printf -- '-s\nread-only')" "${argv}"
assert_contains "git repo check skipped (isolated dir)" "--skip-git-repo-check" "${argv}"
assert_contains "ephemeral session" "--ephemeral" "${argv}"
cdir="$(printf '%s\n' "${argv}" | awk 'p{print; exit} $0=="-C"{p=1}')"
assert_not_contains "-C is not the project or HOME" "${PROJECT_ROOT}" "${cdir}"
assert_equals "codex ran from the same isolated dir it was pointed at" "${cdir}" "$(cat "${REC}/1/cwd" 2>/dev/null)"
case "${cdir}" in */consult-iso.*) iso_ok=yes ;; *) iso_ok=no ;; esac
assert_equals "the isolated dir is a fresh consult-iso scratch dir" "yes" "${iso_ok}"
assert_equals "codex received exactly the frozen package on stdin" "$(cat "${PKGF}")" "$(cat "${REC}/1/stdin")"
assert_contains "prints where the answer is" "answer.md" "${OUT}"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "second send of one approval -> 4" "4" "${RC}"
assert_equals "second send never reaches codex" "1" "$(calls)"
assert_contains "refusal says not approved" "NOT APPROVED" "${OUT}"

echo "-- send: refusals that must not reach codex --"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "no approval -> 4" "4" "${RC}"
assert_equals "no approval: codex not invoked" "0" "$(calls)"

reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_dec "Do not send"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "declined -> 4" "4" "${RC}"

reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_old
r="${H}/.claude/.skill-egress-receipt-${TOK}.${D}.toolu_old"
jq -c '.ts -= 1000' "${r}" > "${r}.x" && mv "${r}.x" "${r}"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "stale approval -> 4" "4" "${RC}"
assert_equals "stale approval: codex not invoked" "0" "$(calls)"

reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_fut
r="${H}/.claude/.skill-egress-receipt-${TOK}.${D}.toolu_fut"
jq -c '.ts += 100000' "${r}" > "${r}.x" && mv "${r}.x" "${r}"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "future-dated approval -> 4" "4" "${RC}"

reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_empty
: > "${H}/.claude/.skill-egress-receipt-${TOK}.${D}.toolu_empty"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "empty receipt file -> 4" "4" "${RC}"

reset; printf 'other package\n' > "${T}/other.md"
dispatch "${P_FULL}" "${SID}" prepare codex "${T}/other.md"
D2="$(printf '%s' "${OUT}" | sed -n 's/^digest: \([0-9a-f]\{64\}\)$/\1/p' | head -1)"
dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D2}" "other package" toolu_o
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "approval of another package does not authorise this one -> 4" "4" "${RC}"

reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_tam
printf 'EXTRA: exfiltrate\n' >> "${H}/.claude/.skill-egress-pkg-${TOK}.${D}"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "package altered after prepare -> 3" "3" "${RC}"
assert_equals "altered package: codex not invoked" "0" "$(calls)"
assert_equals "altered package: approval NOT consumed" "1" \
    "$(ls "${H}"/.claude/.skill-egress-receipt-"${TOK}".* 2>/dev/null | grep -vc consumed)"

reset; dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "never prepared -> 4" "4" "${RC}"

reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_ns
dispatch "${P_FULL}" - send "${D}"
assert_equals "no own session identity -> 3" "3" "${RC}"
assert_contains "no identity: says verification could not run" "CANNOT VERIFY" "${OUT}"
assert_not_contains "no identity: does not tell the user to approve again" "Ask the user again" "${OUT}"
assert_equals "no identity: codex not invoked" "0" "$(calls)"

dispatch "${P_NOJQ}" "${SID}" send "${D}"
assert_equals "no jq -> 3" "3" "${RC}"
assert_contains "no jq named" "jq" "${OUT}"
assert_equals "no jq: codex not invoked" "0" "$(calls)"

echo "-- send: secret scan --"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_gl3
echo 3 > "${T}/gitleaks.rc"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "gitleaks findings -> 6" "6" "${RC}"
assert_equals "findings: codex not invoked" "0" "$(calls)"
assert_equals "findings: approval NOT consumed (nothing was attempted)" "1" \
    "$(ls "${H}"/.claude/.skill-egress-receipt-"${TOK}".* 2>/dev/null | grep -vc consumed)"
echo 1 > "${T}/gitleaks.rc"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "gitleaks broken -> 3" "3" "${RC}"
assert_equals "gitleaks broken: codex not invoked" "0" "$(calls)"
rm -f "${T}/gitleaks.rc"
dispatch "${P_NOGITLEAKS}" "${SID}" send "${D}"
assert_equals "gitleaks absent -> still sends" "0" "${RC}"
assert_contains "gitleaks absent is announced" "NOT secret-scanned" "${OUT}"

echo "-- send: escape hatch --"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
printf '{"consultation":{"egress_consent":"warn"}}' > "${H}/.claude/skill-config.json"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "warn mode sends without an approval" "0" "${RC}"
assert_contains "warn mode announces enforcement is OFF" "consent enforcement is OFF" "${OUT}"
printf '{"consultation":{"egress_consent":"WARN"}}' > "${H}/.claude/skill-config.json"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "any other value enforces -> 4" "4" "${RC}"
printf 'not json' > "${H}/.claude/skill-config.json"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "unreadable config enforces -> 4" "4" "${RC}"

echo "-- send: execution failure and parallel approvals --"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_f
echo 1 > "${T}/codex.rc"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "codex failure -> 5" "5" "${RC}"
assert_contains "failure says it may have sent" "MAY HAVE SENT" "${OUT}"
rm -f "${T}/codex.rc"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "after an uncertain send the approval is gone -> 4" "4" "${RC}"

reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_p1; approve "${D}" "${PKG}" toolu_p2
dispatch "${P_FULL}" "${SID}" send "${D}"; rc1="${RC}"
dispatch "${P_FULL}" "${SID}" send "${D}"; rc2="${RC}"
dispatch "${P_FULL}" "${SID}" send "${D}"; rc3="${RC}"
assert_equals "two approvals authorise exactly two sends" "0 0 4" "${rc1} ${rc2} ${rc3}"

echo "-- usage --"
dispatch "${P_FULL}" "${SID}" send "not-a-digest"
assert_equals "invalid digest -> 2" "2" "${RC}"
dispatch "${P_FULL}" "${SID}" send "${D}" --model 'x;rm -rf /'
assert_equals "unsafe model name -> 2" "2" "${RC}"
dispatch "${P_FULL}" "${SID}" frobnicate
assert_equals "unknown command -> 2" "2" "${RC}"

print_summary
