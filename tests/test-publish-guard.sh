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

rm -rf "${WORK}"
print_summary
exit $?
