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
            mkdir chmod stat find head tail wc env mktemp cmp grep printf ln ls rmdir sleep iconv readlink; do
    src="$(command -v "${tool}" 2>/dev/null)"; [ -n "${src}" ] && [ -x "${src}" ] && ln -sf "${src}" "${TOOLS}/${tool}"
done
JQD="${T}/jqd"; mkdir -p "${JQD}"; ln -sf "$(command -v jq)" "${JQD}/jq"
STUBS="${T}/stubs"; mkdir -p "${STUBS}"
REC="${T}/codex-calls"; mkdir -p "${REC}"
cat > "${STUBS}/codex" <<EOF
#!/bin/bash
n=\$(ls "${REC}" | wc -l | tr -d ' '); n=\$((n + 1)); d="${REC}/\${n}"; mkdir -p "\$d"
printf '%s\n' "\$@" > "\$d/argv"; cat > "\$d/stdin"; pwd > "\$d/cwd"; env > "\$d/env"
out=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
[ -f "${T}/codex.rc" ] && exit "\$(cat "${T}/codex.rc")"
[ -n "\$out" ] && printf 'OK from stub\n' > "\$out"
exit 0
EOF
cat > "${STUBS}/gitleaks" <<EOF
#!/bin/bash
# Mirrors real gitleaks 8.30: GITLEAKS_CONFIG / GITLEAKS_CONFIG_TOML or a .gitleaks.toml
# in the working directory replace the rules — modelled here as "finds nothing".
in="\$(cat)"
pwd > "${T}/gitleaks.cwd"
ignore_allow=no; ipath=.
while [ \$# -gt 0 ]; do case "\$1" in --ignore-gitleaks-allow) ignore_allow=yes ;; -i|--gitleaks-ignore-path) ipath="\$2"; shift ;; esac; shift; done
case "\$in" in *gitleaks:allow*) [ "\$ignore_allow" = yes ] || exit 0 ;; esac
[ -f "\$ipath/.gitleaksignore" ] && exit 0
[ -f "${T}/gitleaks.sleep" ] && sleep "\$(cat "${T}/gitleaks.sleep")"
if [ -n "\${GITLEAKS_CONFIG:-}" ] || [ -n "\${GITLEAKS_CONFIG_TOML:-}" ] || [ -f .gitleaks.toml ]; then exit 0; fi
exit "\$(cat "${T}/gitleaks.rc" 2>/dev/null || echo 0)"
EOF
chmod +x "${STUBS}/codex" "${STUBS}/gitleaks"
NOGL="${T}/nogl"; mkdir -p "${NOGL}"; ln -sf "${STUBS}/codex" "${NOGL}/codex"
P_FULL="${STUBS}:${JQD}:${TOOLS}"
P_NOGITLEAKS="${NOGL}:${JQD}:${TOOLS}"
P_NOJQ="${STUBS}:${TOOLS}"

calls() { ls "${REC}" | wc -l | tr -d ' '; }
# The dispatcher keeps each successful run's answer dir under TMPDIR; point it at this
# test's own temp dir so a suite run does not leave hundreds of them in the user's TMPDIR.
export TMPDIR="${T}/tmp"; mkdir -p "${TMPDIR}"
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
            options:[{label:"Do not send", description:"keep"},
                     {label:"Approve and send", description:"send", preview:$p}]}]}}')"
    hook "${ASK_HOOK}" "${_pre}"
    [ "${_label}" = "Approve and send" ] && _ann="$(jq -nc --arg q "${_q}" --arg p "$2" '{($q):{preview:$p}}')"
    _post="$(printf '%s' "${_pre}" | jq -c --arg q "${_q}" --arg l "${_label}" --argjson a "${_ann}" \
        '.hook_event_name="PostToolUse" | .tool_input.answers={($q):$l} | .tool_input.annotations=$a
         | .tool_response={questions:.tool_input.questions, answers:{($q):$l}, annotations:$a}')"
    hook "${RCPT_HOOK}" "${_post}"
}
reset() { rm -f "${H}"/.claude/.skill-egress-* "${T}/codex.rc" "${T}/gitleaks.rc" "${T}/gitleaks.sleep" "${T}/gitleaks.cwd" "${T}/.gitleaks.toml" "${H}/.claude/skill-config.json"; rm -rf "${REC:?}"/*; }

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
# Measured live 2026-09-16: without these, `codex exec` from an empty dir still ran 18
# user/plugin hooks and started MCP servers — context the preview never showed.
assert_contains "user config ignored (no plugins/MCP from config.toml)" "--ignore-user-config" "${argv}"
for feat in hooks plugins memories apps; do
    assert_contains "feature '${feat}' disabled" "$(printf -- '--disable\n%s' "${feat}")" "${argv}"
done
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
approve "${D}" "${PKG}" toolu_yes_first
approve "${D}" "${PKG}" toolu_then_decline "Do not send"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "approve then decline the same package -> 4 (latest answer wins)" "4" "${RC}"
assert_equals "approve then decline: codex not invoked" "0" "$(calls)"

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
# Sequential asks: each ask supersedes the previous one, so only the latest approval counts.
approve "${D}" "${PKG}" toolu_p1; approve "${D}" "${PKG}" toolu_p2
dispatch "${P_FULL}" "${SID}" send "${D}"; rc1="${RC}"
dispatch "${P_FULL}" "${SID}" send "${D}"; rc2="${RC}"
assert_equals "two sequential approvals of one package authorise ONE send (the latest supersedes)" "0 4" "${rc1} ${rc2}"
# Parallel asks (both asked before either is answered) approved twice authorise two sends.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
qq="Send to Codex? [egress-consent:${D}]"
for id in toolu_pp1 toolu_pp2; do
    hook "${ASK_HOOK}" "$(jq -nc --arg id "$id" --arg tp "${TP}" --arg q "${qq}" --arg p "${PKG}" \
        '{transcript_path:$tp, tool_use_id:$id, agent_id:null, tool_input:{questions:[{question:$q, header:"E", multiSelect:false,
          options:[{label:"Do not send", description:"k"},{label:"Approve and send", description:"s", preview:$p}]}]}}')"
done
for id in toolu_pp1 toolu_pp2; do
    hook "${RCPT_HOOK}" "$(jq -nc --arg id "$id" --arg tp "${TP}" --arg q "${qq}" --arg p "${PKG}" \
        '{transcript_path:$tp, tool_use_id:$id, agent_id:null,
          tool_response:{questions:[{question:$q}], answers:{($q):"Approve and send"}, annotations:{($q):{preview:$p}}}}')"
done
dispatch "${P_FULL}" "${SID}" send "${D}"; rc1="${RC}"
dispatch "${P_FULL}" "${SID}" send "${D}"; rc2="${RC}"
dispatch "${P_FULL}" "${SID}" send "${D}"; rc3="${RC}"
assert_equals "two parallel approvals authorise exactly two sends" "0 0 4" "${rc1} ${rc2} ${rc3}"

echo "-- review round 1 (silent-failure + code review) --"
unconsumed() { ls "${H}"/.claude/.skill-egress-receipt-"${TOK}".* 2>/dev/null | grep -Evc 'consumed|revoked'; }

# H2: the package must not change between verification and sending.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_race
echo 2 > "${T}/gitleaks.sleep"
( sleep 1; printf 'SECRET=hunter2\n' > "${H}/.claude/.skill-egress-pkg-${TOK}.${D}" ) &
dispatch "${P_FULL}" "${SID}" send "${D}"; wait
if [ "${RC}" = "0" ]; then
    assert_equals "H2: a package rewritten mid-send is not what gets sent" "$(cat "${PKGF}")" "$(cat "${REC}/1/stdin" 2>/dev/null)"
else
    assert_equals "H2: a package rewritten mid-send is refused or sent unmodified" "0" "$(calls)"
fi
assert_not_contains "H2: the secret written mid-send never reaches codex" "hunter2" "$(cat "${REC}"/*/stdin 2>/dev/null)"

# H3: the secret scan cannot be switched off from the environment or the caller's cwd.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_glenv
echo 3 > "${T}/gitleaks.rc"
OUT="$(cd "${T}" && env PATH="${P_FULL}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" CLAUDE_CODE_SESSION_ID="${SID}" \
    GITLEAKS_CONFIG="${T}/weak.toml" GITLEAKS_CONFIG_TOML='x' /bin/bash "${DISPATCH}" send "${D}" 2>&1 < /dev/null)"; RC=$?
assert_equals "H3: GITLEAKS_CONFIG in the environment does not disable the scan" "6" "${RC}"
printf 'x' > "${T}/.gitleaks.toml"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "H3: a .gitleaks.toml in the caller's cwd does not disable the scan" "6" "${RC}"
case "$(cat "${T}/gitleaks.cwd" 2>/dev/null)" in */consult-iso.*) glcwd=isolated ;; "") glcwd=not-run ;; *) glcwd="$(cat "${T}/gitleaks.cwd")" ;; esac
assert_equals "H3: gitleaks runs from the isolated directory" "isolated" "${glcwd}"
assert_equals "H3: findings still leave the approval unused" "1" "$(unconsumed)"

# M4: no hasher is reported as that, not as tampering.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_nohash
NOHASH="${T}/nohash"; mkdir -p "${NOHASH}"
for f in "${TOOLS}"/*; do case "$(basename "$f")" in shasum|sha256sum|perl) ;; *) ln -sf "$(readlink "$f")" "${NOHASH}/$(basename "$f")" ;; esac; done
dispatch "${STUBS}:${JQD}:${NOHASH}" "${SID}" send "${D}"
assert_equals "M4: no hasher -> 3" "3" "${RC}"
assert_contains "M4: says the package could not be hashed" "could not hash" "${OUT}"
assert_not_contains "M4: does not blame a modified package" "modified after prepare" "${OUT}"

# L7: scratch-dir failure happens BEFORE the approval is used.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_tmpd
OUT="$(cd "${T}" && env PATH="${P_FULL}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" CLAUDE_CODE_SESSION_ID="${SID}" \
    TMPDIR="${T}/does-not-exist" /bin/bash "${DISPATCH}" send "${D}" 2>&1 < /dev/null)"; RC=$?
assert_equals "L7: no scratch dir -> 3 (nothing was sent)" "3" "${RC}"
assert_equals "L7: the approval is not used" "1" "$(unconsumed)"

# Code review minors.
dispatch "${P_FULL}" "${SID}" send "${D}" --model -sdanger-full-access
assert_equals "a model name starting with '-' -> 2" "2" "${RC}"
printf '\n\n\n' > "${T}/blank.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/blank.md"
assert_equals "a newline-only package -> 2" "2" "${RC}"
printf 'caf\351\n' > "${T}/latin1.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/latin1.md"
assert_equals "a package that is not UTF-8 -> 2" "2" "${RC}"

# H1 (dispatcher view): a decline whose payload is not the expected shape still revokes.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_h1a
q="Send to Codex? [egress-consent:${D}]"
pre="$(jq -nc --arg id toolu_h1b --arg tp "${TP}" --arg q "${q}" --arg p "${PKG}" \
    '{transcript_path:$tp, tool_use_id:$id, agent_id:null, tool_input:{questions:[{question:$q, header:"E", multiSelect:false,
      options:[{label:"Do not send", description:"k"},{label:"Approve and send", description:"s", preview:$p}]}]}}')"
hook "${ASK_HOOK}" "${pre}"
hook "${RCPT_HOOK}" "$(printf '%s' "${pre}" | jq -c '.tool_response="User declined"')"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "H1: re-asking about a package and getting an odd answer leaves no usable approval -> 4" "4" "${RC}"

# H1: re-asking alone (e.g. the user then cancels, so no PostToolUse ever fires) revokes.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_h1c
hook "${ASK_HOOK}" "$(printf '%s' "${pre}" | jq -c '.tool_use_id="toolu_h1d"')"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "H1: asking again about a package supersedes the earlier approval -> 4" "4" "${RC}"

echo "-- review round 2 (adversarial) --"
# A3: an allow comment in the package, or a .gitleaksignore in the caller's cwd.
reset; printf 'token here # gitleaks:allow\n' > "${T}/allow.md"
dispatch "${P_FULL}" "${SID}" prepare codex "${T}/allow.md"
DA="$(printf '%s' "${OUT}" | sed -n 's/^digest: \([0-9a-f]\{64\}\)$/\1/p' | head -1)"
approve "${DA}" "$(cat "${T}/allow.md")" toolu_a3a
echo 3 > "${T}/gitleaks.rc"
dispatch "${P_FULL}" "${SID}" send "${DA}"
assert_equals "A3: a gitleaks:allow comment in the package does not silence the scan" "6" "${RC}"
# Independent of the allow comment: a clean package, and an ignore file in the caller's cwd.
# Two defences overlap here (gitleaks runs from the isolated dir AND gets an explicit empty
# ignore path), so this cell only goes red when BOTH are removed.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_a3b
echo 3 > "${T}/gitleaks.rc"
: > "${T}/.gitleaksignore"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "A3: a .gitleaksignore in the caller's cwd does not silence the scan" "6" "${RC}"
rm -f "${T}/.gitleaksignore"

# Control characters that could hide text in a preview are refused.
printf 'visible\033[8mhidden\033[0m\n' > "${T}/esc.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/esc.md"
assert_equals "an ESC control sequence in the package -> 2" "2" "${RC}"
printf 'a\r\n' > "${T}/cr.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/cr.md"
assert_equals "a carriage return in the package -> 2" "2" "${RC}"
printf 'a\tb\n' > "${T}/tab.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/tab.md"
assert_equals "control: a tab is fine" "0" "${RC}"

# Relative TMPDIR and a TMPDIR inside a git repository refuse before claiming.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_reltmp
mkdir -p "${T}/reltmp"
OUT="$(cd "${T}" && env PATH="${P_FULL}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" CLAUDE_CODE_SESSION_ID="${SID}" \
    TMPDIR="reltmp" /bin/bash "${DISPATCH}" send "${D}" 2>&1 < /dev/null)"; RC=$?
assert_equals "a relative TMPDIR still sends from an absolute isolated dir" "0" "${RC}"
case "$(cat "${REC}/1/cwd" 2>/dev/null)" in /*) abs=yes ;; *) abs=no ;; esac
assert_equals "codex was pointed at an absolute directory" "yes" "${abs}"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_gittmp
mkdir -p "${T}/repo/tmp"; git -C "${T}/repo" init -q 2>/dev/null
ln -sf "$(command -v git)" "${TOOLS}/git"
OUT="$(cd "${T}" && env PATH="${P_FULL}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" CLAUDE_CODE_SESSION_ID="${SID}" \
    TMPDIR="${T}/repo/tmp" /bin/bash "${DISPATCH}" send "${D}" 2>&1 < /dev/null)"; RC=$?
assert_equals "a TMPDIR inside a git repository -> 3 (codex would load its AGENTS.md)" "3" "${RC}"
assert_equals "git TMPDIR: the approval is not used" "1" "$(unconsumed)"

# A1: parallel asks for one package, the decline's answer processed FIRST.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
q="Send to Codex? [egress-consent:${D}]"
mkpre() { jq -nc --arg id "$1" --arg tp "${TP}" --arg q "${q}" --arg p "${PKG}" \
    '{transcript_path:$tp, tool_use_id:$id, agent_id:null, tool_input:{questions:[{question:$q, header:"E", multiSelect:false,
      options:[{label:"Do not send", description:"k"},{label:"Approve and send", description:"s", preview:$p}]}]}}'; }
mkpost() { local a='{}'; [ "$2" = "Approve and send" ] && a="$(jq -nc --arg q "${q}" --arg p "${PKG}" '{($q):{preview:$p}}')"
    mkpre "$1" | jq -c --arg q "${q}" --arg l "$2" --argjson a "${a}" '.tool_response={questions:.tool_input.questions, answers:{($q):$l}, annotations:$a}'; }
hook "${ASK_HOOK}" "$(mkpre toolu_par_yes)"; hook "${ASK_HOOK}" "$(mkpre toolu_par_no)"
hook "${RCPT_HOOK}" "$(mkpost toolu_par_no "Do not send")"
hook "${RCPT_HOOK}" "$(mkpost toolu_par_yes "Approve and send")"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "A1: a decline answered before a parallel approval still wins -> 4" "4" "${RC}"
assert_equals "A1: codex not invoked" "0" "$(calls)"

# A2: declining a REVISED package withdraws the older package's approval too.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_a2old
printf 'revised package\n' > "${T}/rev.md"; dispatch "${P_FULL}" "${SID}" prepare codex "${T}/rev.md"
D3="$(printf '%s' "${OUT}" | sed -n 's/^digest: \([0-9a-f]\{64\}\)$/\1/p' | head -1)"
approve "${D3}" "revised package" toolu_a2new "Do not send"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "A2: declining any consent question withdraws other unused approvals -> 4" "4" "${RC}"

# A2: a new user prompt ends the turn the approval was given in.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_turn
hook "${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh" "$(jq -nc --arg tp "${TP}" '{hook_event_name:"UserPromptSubmit", transcript_path:$tp, prompt:"actually no"}')"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "A2: an approval does not survive into the next user turn -> 4" "4" "${RC}"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_turn_ctl
hook "${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh" "$(jq -nc --arg tp "${H}/.claude/projects/p/OTHER.jsonl" '{hook_event_name:"UserPromptSubmit", transcript_path:$tp, prompt:"hi"}')"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "control: another conversation's prompt does not withdraw this approval" "0" "${RC}"

echo "-- review round 3 --"
# F2: a parallel decline wins even when a second boundary falls between the two asks.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
hook "${ASK_HOOK}" "$(mkpre toolu_f2_no)"
sleep 1.1
hook "${ASK_HOOK}" "$(mkpre toolu_f2_yes)"
hook "${RCPT_HOOK}" "$(mkpost toolu_f2_no "Do not send")"
hook "${RCPT_HOOK}" "$(mkpost toolu_f2_yes "Approve and send")"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "F2: a parallel decline wins across a second boundary -> 4" "4" "${RC}"
# F3: decline, then re-ask and approve within the same second — a genuine new approval.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
hook "${ASK_HOOK}" "$(mkpre toolu_f3_no)"; hook "${RCPT_HOOK}" "$(mkpost toolu_f3_no "Do not send")"
hook "${ASK_HOOK}" "$(mkpre toolu_f3_yes)"; hook "${RCPT_HOOK}" "$(mkpost toolu_f3_yes "Approve and send")"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "F3: a re-ask answered after the decline is a valid approval -> 0" "0" "${RC}"
# F4: an unusable TMPDIR is reported as that, not as hidden characters.
OUT="$(cd "${T}" && env PATH="${P_FULL}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" CLAUDE_CODE_SESSION_ID="${SID}" \
    TMPDIR="${T}/nope-tmp" /bin/bash "${DISPATCH}" prepare codex "${PKGF}" 2>&1 < /dev/null)"; RC=$?
assert_equals "F4: prepare with an unusable TMPDIR still works (no temp file needed)" "0" "${RC}"
assert_not_contains "F4: no false hidden-character claim" "control characters" "${OUT}"
# F6: an exported GIT_DIR does not make a clean TMPDIR look like a repository.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_f6
OUT="$(cd "${T}" && env PATH="${P_FULL}" HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" CLAUDE_CODE_SESSION_ID="${SID}" \
    GIT_DIR="${T}/repo/.git" /bin/bash "${DISPATCH}" send "${D}" 2>&1 < /dev/null)"; RC=$?
assert_equals "F6: GIT_DIR in the environment does not cause a false refusal -> 0" "0" "${RC}"
assert_not_contains "F6: codex does not inherit GIT_DIR" "GIT_DIR=" "$(cat "${REC}/1/env" 2>/dev/null)"

echo "-- review round 4 (Codex + live) --"
# LIVE 2026-09-17: a background-task notification is delivered as UserPromptSubmit with a
# "<task-notification>" prompt. It is not the user speaking and must not end the approval.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_notif
hook "${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh" "$(jq -nc --arg tp "${TP}" \
    '{hook_event_name:"UserPromptSubmit", transcript_path:$tp, prompt:"<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>"}')"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "a task notification does not withdraw the approval -> 0" "0" "${RC}"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_notif2
hook "${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh" "$(jq -nc --arg tp "${TP}" \
    '{hook_event_name:"UserPromptSubmit", transcript_path:$tp, prompt:"no wait, <task-notification> is not what I meant"}')"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "control: a real prompt that merely mentions the tag still withdraws -> 4" "4" "${RC}"

# Codex P1: a decline recorded while a send is between reading the veto and claiming must
# still stop the send; and a receipt published after a decline must not survive it.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
hook "${ASK_HOOK}" "$(mkpre toolu_p1_yes)"; hook "${ASK_HOOK}" "$(mkpre toolu_p1_no)"
hook "${RCPT_HOOK}" "$(mkpost toolu_p1_no "Do not send")"
# Simulate the late publication: a receipt for the approved ask written AFTER the decline,
# as if its PostToolUse had been paused before publishing.
hook "${RCPT_HOOK}" "$(mkpost toolu_p1_yes "Approve and send")"
assert_equals "P1: a receipt published after a decline of an older ask is revoked on publication" "0" "$(unconsumed)"
# Post-claim re-check. The only command between the dispatcher's first veto read and its
# claim is the jq that reads each receipt, so a jq wrapper plants a decline exactly there.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_p1c
REALJQ="$(command -v jq)"
mkdir -p "${T}/latejq"
cat > "${T}/latejq/jq" <<EOF
#!/bin/bash
case "\$*" in
    *ask_ms*) printf '%s' "\$(( \$(date +%s) * 1000 + 999 ))" > "${H}/.claude/.skill-egress-veto-${TOK}.${D}.late" ;;
esac
exec "${REALJQ}" "\$@"
EOF
chmod +x "${T}/latejq/jq"
dispatch "${T}/latejq:${STUBS}:${TOOLS}" "${SID}" send "${D}"
assert_equals "P1: a decline landing after the veto was first read still stops the send -> 4" "4" "${RC}"
assert_equals "P1: codex not invoked" "0" "$(calls)"

echo "-- review round 5 --"
TURN="${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh"
turn() { hook "${TURN}" "$(jq -nc --arg tp "$1" --arg p "$2" '{hook_event_name:"UserPromptSubmit", transcript_path:$tp, prompt:$p}')"; }
# The REAL payload of a background-Bash notification, captured live 2026-09-17 (path redacted).
NOTIF="$(cat "${PROJECT_ROOT}/tests/fixtures/egress-consent/task-notification-bash.txt")"
# A real prompt that STARTS with a pasted notification block, then says no, is the user.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r5a
turn "${TP}" "${NOTIF}
No - do NOT send that to codex."
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R5: a notification block followed by the user's own text withdraws -> 4" "4" "${RC}"
# Pure notifications, including leading whitespace and two blocks, do not.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r5b
turn "${TP}" "$(printf '\t\n  %s\n%s\n' "${NOTIF}" "${NOTIF}")"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R5: whitespace-prefixed, repeated notification blocks do not withdraw -> 0" "0" "${RC}"
# User text BETWEEN two blocks, or before a stray closing tag, is the user.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r6a
turn "${TP}" "${NOTIF}
No - do NOT send that to codex.
${NOTIF}"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R6: user text between two notification blocks withdraws -> 4" "4" "${RC}"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r6b
turn "${TP}" "${NOTIF}
No - do NOT send.
</task-notification>"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R6: user text before a stray closing tag withdraws -> 4" "4" "${RC}"
# A nested opening tag inside a block is not a notification shape.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r7a
assert_equals "R7 setup: the approval exists before the prompt" "1" "$(unconsumed)"
turn "${TP}" "<task-notification>
<task-notification>
no, do not send
</task-notification>"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R7: a nested opening tag inside a block withdraws -> 4" "4" "${RC}"
# A nested block opened on the SAME line as the outer one is not a notification either.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r7b
assert_equals "R7b setup: the approval exists before the prompt" "1" "$(unconsumed)"
turn "${TP}" "<task-notification><task-notification>
no, do not send
</task-notification>"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R7b: a same-line nested opening tag withdraws -> 4" "4" "${RC}"
# Indentation and non-LF line breaks before a nested opening tag are still line starts.
for sep in 'tab' 'cr' 'u2028'; do
    case "${sep}" in
        tab) body="$(printf '<task-notification>\n\t<task-notification>\nno, do not send\n</task-notification>')" ;;
        cr) body="$(printf '<task-notification>\nno, do not send\r<task-notification>\n</task-notification>')" ;;
        u2028) body="$(printf '<task-notification>\nno, do not send\342\200\250<task-notification>\n</task-notification>')" ;;
    esac
    reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
    approve "${D}" "${PKG}" "toolu_r7c_${sep}"
    turn "${TP}" "${body}"
    dispatch "${P_FULL}" "${SID}" send "${D}"
    assert_equals "R7c: a nested block after ${sep} withdraws -> 4" "4" "${RC}"
done
# If the classifier itself fails (regex engine limit on a huge prompt), approvals are
# WITHDRAWN — the safe direction — and the message says so.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r9
python3 -c "print('<task-notification>' + 'x' * 7000000 + '\nno, do not send')" > "${T}/huge.txt"
OUT="$(jq -nc --arg tp "${TP}" --rawfile p "${T}/huge.txt" '{hook_event_name:"UserPromptSubmit", transcript_path:$tp, prompt:$p}' \
    | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh" 2>/dev/null)"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R9: a prompt the classifier cannot evaluate withdraws -> 4" "4" "${RC}"
assert_not_contains "R9: not misreported as unparseable" "unparseable" "${OUT}"
rm -f "${T}/huge.txt"
# A genuine notification that QUOTES the tag mid-line (a command description, an agent
# result about this very feature) is still a notification.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r8a
QUOTED="$(printf '%s\n' "${NOTIF}" | sed 's|<summary>.*</summary>|<summary>Background command "Check <task-notification> parsing" completed (exit code 0)</summary>|')"
turn "${TP}" "${QUOTED}"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R8: a notification quoting the opening tag mid-line keeps the approval -> 0" "0" "${RC}"
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r8b
turn "${TP}" "<task-notification>
<task-id>a1</task-id>
<status>completed</status>
<result>The fix now rejects a nested <task-notification> opening tag at the start of a line.</result>
</task-notification>"
dispatch "${P_FULL}" "${SID}" send "${D}"
assert_equals "R8: an agent result mentioning the opening tag mid-line keeps the approval -> 0" "0" "${RC}"
# A newline inside transcript_path is announced, never a silent wrong-token no-op.
reset; dispatch "${P_FULL}" "${SID}" prepare codex "${PKGF}"
approve "${D}" "${PKG}" toolu_r5c
OUT="$(jq -nc --arg tp "${H}/.claude/projects/p/x
${SID}.jsonl" '{hook_event_name:"UserPromptSubmit", transcript_path:$tp, prompt:"no, do not send"}' \
    | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${TURN}" 2>/dev/null)"
assert_contains "R5: a transcript_path with a newline is announced" "NOT withdrawn" "${OUT}"

echo "-- usage --"
dispatch "${P_FULL}" "${SID}" send "not-a-digest"
assert_equals "invalid digest -> 2" "2" "${RC}"
dispatch "${P_FULL}" "${SID}" send "${D}" --model 'x;rm -rf /'
assert_equals "unsafe model name -> 2" "2" "${RC}"
dispatch "${P_FULL}" "${SID}" frobnicate
assert_equals "unknown command -> 2" "2" "${RC}"

print_summary
