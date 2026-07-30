#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-publish-guard.sh ==="

GUARD="${PROJECT_ROOT}/hooks/publish-guard.sh"

WORK="$(mktemp -d /tmp/pg-XXXXXX)"
MEM="${WORK}/memory"; REPO="${WORK}/repo"
mkdir -p "${MEM}" "${REPO}"

PRIVATE_RUN="the verdict artifact carries the head sha at verify time so an ancestor failure never blocks a commit that has since been repaired"
printf 'name: v\n---\n\n%s\n' "${PRIVATE_RUN}" > "${MEM}/feedback_verdict_sha.md"
( cd "${REPO}" && git init -q . && printf 'unrelated\n' > r.md && git add r.md \
  && git -c user.email=t@t -c user.name=t commit -q -m init )

printf 'Proposal.\n\n%s\n' "${PRIVATE_RUN}" > "${WORK}/leaky.md"
printf 'Evidence: memory/feedback_verdict_sha.md:4 (feedback, 2026-07-29).\n' > "${WORK}/clean.md"

_run() {  # _run <command>
    jq -n --arg c "$1" '{"tool_input":{"command":$c}}' \
    | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null )
}

out="$(_run "gh issue create --title t --body-file ${WORK}/leaky.md")"
assert_contains "leaky issue create is denied" '"deny"' "${out:-<empty>}"
assert_contains "deny names the source file" "feedback_verdict_sha.md" "${out:-}"
assert_not_contains "deny does not echo matched text" "verdict artifact carries the head sha" "${out:-}"

out="$(_run "gh issue create --title t --body-file ${WORK}/clean.md")"
assert_equals "clean issue create is allowed silently" "" "${out:-}"

out="$(_run "gh issue comment 12 --body-file ${WORK}/leaky.md")"
assert_contains "leaky issue comment is denied" '"deny"' "${out:-<empty>}"

out="$(_run "gh issue edit 12 --body-file ${WORK}/leaky.md")"
assert_contains "leaky issue edit is denied" '"deny"' "${out:-<empty>}"

out="$(_run "gh pr create --title t --body \"${PRIVATE_RUN}\"")"
assert_contains "leaky inline --body is denied" '"deny"' "${out:-<empty>}"

out="$(_run 'git push origin main')"
assert_equals "git push is untouched by this hook" "" "${out:-}"

out="$(_run 'gh issue list --limit 5')"
assert_equals "gh issue list is untouched" "" "${out:-}"

out="$(_run 'ls -la')"
assert_equals "unrelated command is untouched" "" "${out:-}"

out="$(_run 'gh pr merge 3 --squash')"
assert_equals "gh pr merge is not this hook's business" "" "${out:-}"

# gh api is a publication path too (issue #174 gap: it carried zero scan).
# The engine scans the WHOLE command string, so an inline -f body=... on a
# gh api write endpoint is caught with no body-file parsing needed.
out="$(_run "gh api repos/o/r/issues -f body=\"${PRIVATE_RUN}\"")"
assert_contains "leaky gh api issues create (-f, implicit POST) is denied" '"deny"' "${out:-<empty>}"

out="$(_run "gh api --method POST repos/o/r/issues/1/comments -f body=\"${PRIVATE_RUN}\"")"
assert_contains "leaky gh api issue comment (--method POST before endpoint) is denied" '"deny"' "${out:-<empty>}"

out="$(_run 'gh api repos/o/r/issues -f body="clean text, nothing private here"')"
assert_equals "clean gh api issues create is allowed silently" "" "${out:-}"

out="$(_run 'gh api repos/o/r/pulls/3/merge --method PUT')"
assert_equals "gh api pulls merge is not this hook's business" "" "${out:-}"

out="$(_run 'gh api repos/o/r/issues')"
assert_equals "gh api bare read (no fields/method) is untouched" "" "${out:-}"

# gh api --input / -F name=@path: the body lives in a FILE gh reads directly,
# not inline in the command string. Before this fix (issue #174 round, I1)
# gh_publish_body_files emitted no path for ANY `api` verb, so these forms
# passed with the body never read and nothing announced.
out="$(_run "gh api repos/o/r/issues --method POST --input ${WORK}/leaky.md")"
assert_contains "leaky gh api --input file is denied" '"deny"' "${out:-<empty>}"

out="$(_run "gh api repos/o/r/issues -X POST -F body=@${WORK}/leaky.md")"
assert_contains "leaky gh api -F name=@path is denied" '"deny"' "${out:-<empty>}"

out="$(_run "gh api repos/o/r/issues --method POST --input ${WORK}/clean.md")"
assert_equals "clean gh api --input file is allowed silently" "" "${out:-}"

# Absent corpus: allow, and say so.
out="$( jq -n --arg c "gh issue create --body-file ${WORK}/leaky.md" '{"tool_input":{"command":$c}}' \
        | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${WORK}/nope" \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null ) )"
assert_not_contains "absent corpus does not deny" '"deny"' "${out:-}"
assert_contains "absent corpus is announced" "could not check" "${out:-<empty>}"

# Long clean body: proves the citation-vs-quote distinction. This body is well
# over the engine's 16-word shingle window and discusses the SAME topic as the
# private memory file — including a proper memory/<file>.md:<line> citation —
# but never reproduces a 16-word verbatim run from the corpus. It must be
# ALLOWED; a body this long could trivially trip a naive "mentions the topic"
# or "long body" heuristic, which is exactly what this case rules out.
LONG_CLEAN="Summary of the push-gate verdict work for this PR. The verdict artifact
now records a commit sha at write time, which lets the gate distinguish a
failure measured against an old commit from one measured against the current
HEAD. Historically an ancestor failure could block a commit that had already
fixed the underlying issue, which was confusing for contributors and eroded
trust in the gate. The fix means an ancestor verdict is only ever advisory,
never a hard deny, while a HEAD-fresh failing verdict still blocks the push
as intended. See memory/feedback_verdict_sha.md:4 for the original reasoning
and the discussion that led to this design. No further action is needed here;
this is background context for reviewers who want to understand why the
sha field was added and how it changes push-gate behavior going forward."
printf '%s\n' "${LONG_CLEAN}" > "${WORK}/long-clean.md"
out="$(_run "gh issue create --title t --body-file ${WORK}/long-clean.md")"
assert_equals "long clean body with citation and topic prose is allowed" "" "${out:-}"

# --- Fix round 1/5 (#174): inability-to-check paths must ANNOUNCE, never
# silently allow. Stage broken plugin roots that mirror the real one but with
# one required file removed, so the hook's own CLAUDE_PLUGIN_ROOT-relative
# lookups miss it while the guard script itself still runs from its real path.

BROKEN_NO_GITCMD="${WORK}/broken-no-gitcmd"
mkdir -p "${BROKEN_NO_GITCMD}/hooks/lib" "${BROKEN_NO_GITCMD}/scripts"
cp "${PROJECT_ROOT}/scripts/memory-leak-check.sh" "${BROKEN_NO_GITCMD}/scripts/memory-leak-check.sh"
# hooks/lib/git-command.sh deliberately absent.

BROKEN_NO_ENGINE="${WORK}/broken-no-engine"
mkdir -p "${BROKEN_NO_ENGINE}/hooks/lib" "${BROKEN_NO_ENGINE}/scripts"
cp "${PROJECT_ROOT}/hooks/lib/git-command.sh" "${BROKEN_NO_ENGINE}/hooks/lib/git-command.sh"
# scripts/memory-leak-check.sh deliberately absent.

_run_with_root() {  # _run_with_root <plugin-root> <command>
    jq -n --arg c "$2" '{"tool_input":{"command":$c}}' \
    | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
        CLAUDE_PLUGIN_ROOT="$1" /bin/bash "${GUARD}" 2>/dev/null )
}

out="$(_run_with_root "${BROKEN_NO_GITCMD}" "gh issue create --title t --body-file ${WORK}/leaky.md")"
assert_contains "missing git-command.sh announces instead of silently allowing" "could not check" "${out:-<empty>}"
assert_not_contains "missing git-command.sh does not deny" '"deny"' "${out:-}"

out="$(_run_with_root "${BROKEN_NO_ENGINE}" "gh issue create --title t --body-file ${WORK}/leaky.md")"
assert_contains "missing memory-leak-check.sh announces instead of silently allowing" "could not check" "${out:-<empty>}"
assert_not_contains "missing memory-leak-check.sh does not deny" '"deny"' "${out:-}"

# Control: even with a broken plugin root, a command that never mentions "gh"
# at all must stay completely silent — the "not applicable" filter runs
# BEFORE the library is ever touched, so a broken root cannot cause noise on
# irrelevant commands.
out="$(_run_with_root "${BROKEN_NO_GITCMD}" "ls -la")"
assert_equals "non-gh command stays silent even with a broken plugin root" "" "${out:-}"

# Controls under the normal (working) root: now that inability-to-check paths
# announce, confirm the genuinely-not-this-hook's-business paths still don't.
out="$(_run "gh issue list --limit 5")"
assert_equals "non-publish gh command still emits nothing after the fix" "" "${out:-}"

out="$(_run "gh issue create --title t --body-file ${WORK}/clean.md")"
assert_equals "clean body still emits nothing after the fix" "" "${out:-}"

# jq unavailable: the announce path here must be the jq-free emitter (jq
# itself is what's missing), so build the JSON payload with jq BEFORE
# stripping it from PATH, then invoke the guard without jq in PATH.
NOJQ_BIN="${WORK}/nojq-bin"
mkdir -p "${NOJQ_BIN}"
ln -sf "$(command -v cat)" "${NOJQ_BIN}/cat"

_leaky_payload="$(jq -n --arg c "gh issue create --title t --body-file ${WORK}/leaky.md" '{"tool_input":{"command":$c}}')"
out="$( printf '%s' "${_leaky_payload}" \
        | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PATH="${NOJQ_BIN}" /bin/bash "${GUARD}" 2>/dev/null ) )"
assert_contains "jq unavailable announces instead of silently allowing" "could not check" "${out:-<empty>}"
assert_not_contains "jq unavailable does not deny" '"deny"' "${out:-}"

_ls_payload="$(jq -n --arg c "ls -la" '{"tool_input":{"command":$c}}')"
out="$( printf '%s' "${_ls_payload}" \
        | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PATH="${NOJQ_BIN}" /bin/bash "${GUARD}" 2>/dev/null ) )"
assert_equals "non-gh command with jq missing still stays silent" "" "${out:-}"

# mktemp -d failure: shim ONLY the guard's own pubguard.* template so the
# engine's internal mlc.* mktemp call (used during the corpus probe) still
# succeeds via the real binary — otherwise both calls share TMPDIR and fail
# together, tripping the (separately deferred) unguarded probe-line ERR trap
# instead of exercising this specific guard.
FAKEBIN="${WORK}/fakebin"
mkdir -p "${FAKEBIN}"
cat > "${FAKEBIN}/mktemp" <<'SHIM'
#!/bin/bash
case "$*" in
    *pubguard.*) echo "mktemp: SIMULATED failure" >&2; exit 1 ;;
    *) exec /usr/bin/mktemp "$@" ;;
esac
SHIM
chmod +x "${FAKEBIN}/mktemp"

out="$( jq -n --arg c "gh issue create --title t --body-file ${WORK}/leaky.md" '{"tool_input":{"command":$c}}' \
        | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PATH="${FAKEBIN}:${PATH}" /bin/bash "${GUARD}" 2>/dev/null ) )"
assert_contains "mktemp -d failure announces instead of silently allowing" "could not check" "${out:-<empty>}"
assert_not_contains "mktemp -d failure does not deny" '"deny"' "${out:-}"

# M4: the OTHER direction -- the corpus probe's OWN mktemp (mlc.*, inside
# memory-leak-check.sh) failing must also announce, not silently allow. This
# is the opposite shim from above: only mlc.* fails, pubguard.* still succeeds
# via the real binary. Before the `|| _MEMPROBE=""` guard, this tripped the
# blanket `trap 'exit 0' ERR` on the unguarded top-level assignment and the
# hook exited silently before the guarded mktemp check above ever ran.
FAKEBIN2="${WORK}/fakebin2"
mkdir -p "${FAKEBIN2}"
cat > "${FAKEBIN2}/mktemp" <<'SHIM'
#!/bin/bash
case "$*" in
    *mlc.*) echo "mktemp: SIMULATED failure" >&2; exit 1 ;;
    *) exec /usr/bin/mktemp "$@" ;;
esac
SHIM
chmod +x "${FAKEBIN2}/mktemp"

out="$( jq -n --arg c "gh issue create --title t --body-file ${WORK}/leaky.md" '{"tool_input":{"command":$c}}' \
        | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PATH="${FAKEBIN2}:${PATH}" /bin/bash "${GUARD}" 2>/dev/null ) )"
assert_contains "corpus-probe mktemp failure announces instead of silently allowing" "could not check" "${out:-<empty>}"
assert_not_contains "corpus-probe mktemp failure does not deny" '"deny"' "${out:-}"

rm -rf "${WORK}"
print_summary
exit $?
