#!/usr/bin/env bash
# test-model-routing-regex.sh — Calibration guard for the model-routing probation
# fixture's per-scenario catch-detector regexes.
#
# Each scenario in tests/fixtures/model-routing/review-pack.json carries a single
# `text` assertion that decides whether a code review "caught" that scenario's
# planted bug (probation criterion 2, docs/observability.md). A regex that
# false-positives inflates a weak model's catch rate; one that false-negatives
# understates the baseline. This test extracts each shipped detector from the
# pack and pins it against an adversarial strong/weak sample set so it cannot rot
# silently. Samples are markdown-formatted because real model output is markdown
# (`**bold**`, `code`) — a proximity regex once scored a genuine catch as a miss.
# Hermetic — no model calls. Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-model-routing-regex.sh ==="

PACK="${PROJECT_ROOT}/tests/fixtures/model-routing/review-pack.json"

# det <scenario-id> — echo the shipped catch-detector regex for a scenario.
det() { jq -r --arg id "$1" '.[] | select(.id==$id) | .assertions[0].text' "${PACK}"; }
# expect <CATCH|MISS> <regex> <text> — assert the runner's grep verdict.
expect() {
    local want="$1" re="$2" txt="$3" got
    if printf '%s\n' "${txt}" | grep -E -i -q "${re}"; then got="CATCH"; else got="MISS"; fi
    assert_equals "[${want}] ${txt}" "${want}" "${got}"
}

# --- local-masks-exit-code (medium) ---
echo "-- local-masks-exit-code --"
RE="$(det local-masks-exit-code)"; assert_not_empty "detector present: local-masks" "${RE}"
expect CATCH "${RE}" "captures the exit code of the **\`local\` command itself**, not the exit code of \`jq\`."
expect CATCH "${RE}" "The \`local\` **builtin** returns 0 on successful assignment, regardless of whether jq failed."
expect CATCH "${RE}" "\`local parsed=\$(jq ...)\` **masks** jq's exit status; \$? reflects local."
expect CATCH "${RE}" "\$? holds the status of the local assignment, **not jq**"
expect MISS  "${RE}" "declares a \`local\` variable \`parsed\`. Later it returns exit code 0 on success."
expect MISS  "${RE}" "The function returns proper exit status when the file is fresh."
expect MISS  "${RE}" "You should validate the JSON schema, not just that it parses."

# --- unquoted-test-wordsplit (obvious) ---
echo "-- unquoted-test-wordsplit --"
RE="$(det unquoted-test-wordsplit)"; assert_not_empty "detector present: unquoted" "${RE}"
expect CATCH "${RE}" "\`\$name\` is **unquoted** in the test; if empty or containing spaces \`[ ]\` breaks. Quote it."
expect CATCH "${RE}" "**word splitting**: an unquoted variable in \`[ ]\` errors when the value has spaces or is empty."
expect CATCH "${RE}" "\`[ \$name = admin ]\` becomes \`[ = admin ]\` (unary operator expected) when name is empty — missing quotes."
expect MISS  "${RE}" "The function returns 0 for admin and 1 otherwise; looks correct."
expect MISS  "${RE}" "The comparison is case-sensitive; 'Admin' won't match."
expect MISS  "${RE}" "Add a docstring explaining the admin check."

# --- pipeline-subshell-lost (subtle) ---
echo "-- pipeline-subshell-lost --"
RE="$(det pipeline-subshell-lost)"; assert_not_empty "detector present: subshell" "${RE}"
expect CATCH "${RE}" "the \`while\` loop runs in a **subshell** because it's right of a pipe, so \`total\` is lost — prints 0."
expect CATCH "${RE}" "piping into \`while read\` spawns a subshell; updates to \`total\` don't propagate to the parent, always 0."
expect CATCH "${RE}" "the accumulator never survives the pipeline — the loop body executes in a child shell."
expect MISS  "${RE}" "the function sums byte counts of each path; looks fine."
expect MISS  "${RE}" "consider checking each path exists before reading."
expect MISS  "${RE}" "use \`\$(stat ...)\` instead of \`wc -c\`."
# Adversarial (code-review #2): collateral 'sum is lost' for a missing path must
# not score as catching the subshell bug.
expect MISS  "${RE}" "If a path does not exist \`wc\` emits an error and the sum is lost for that file."

# --- octal-arithmetic (very subtle) ---
echo "-- octal-arithmetic --"
RE="$(det octal-arithmetic)"; assert_not_empty "detector present: octal" "${RE}"
expect CATCH "${RE}" "\`\$((minutes + 0))\` treats \`08\`/\`09\` as **octal** — invalid octal digits, errors 'value too great for base'. Use \`10#\`."
expect CATCH "${RE}" "a leading-zero value like \`09\` is parsed in base 8; 8 and 9 aren't valid octal digits."
expect CATCH "${RE}" "zero-padded minutes break \`\$(( ))\`; force base 10 with \`10#\`."
expect MISS  "${RE}" "the function flags minutes >= 30 as 'late'; logic is fine."
expect MISS  "${RE}" "consider validating that minutes is numeric."
expect MISS  "${RE}" "\`-ge\` is the right comparison operator here."

# --- duplicate-trap-exit (very subtle) ---
echo "-- duplicate-trap-exit --"
RE="$(det duplicate-trap-exit)"; assert_not_empty "detector present: trap" "${RE}"
expect CATCH "${RE}" "the **second** \`trap ... EXIT\` **overwrites** the first — \`tmp_raw\` is never cleaned up."
expect CATCH "${RE}" "EXIT trap is single-slot; re-registering it replaces the earlier handler, leaking \`tmp_raw\`."
expect CATCH "${RE}" "you set two EXIT traps; only the last one runs, so the first cleanup is lost."
expect MISS  "${RE}" "both temp files are created with mktemp; looks fine."
expect MISS  "${RE}" "consider using a single temp dir instead of two files."
expect MISS  "${RE}" "the cleanup removes temp files on exit."
# Adversarial (code-review #2): merely *enumerating* the two traps, without
# grasping that the second replaces the first, must NOT score as a catch.
expect MISS  "${RE}" "There are two trap statements; the second is on the EXIT signal."
expect MISS  "${RE}" "Should use a trap to clean up but the first attempt is incomplete."

# --- systemic-gate-fail-open (systemic / emergent) ---
# The catch requires reasoning about whole-function behavior (no failure path
# exists), not spotting a localized token. Weak samples include description,
# localized nits, and the comment-rationalization trap.
echo "-- systemic-gate-fail-open --"
RE="$(det systemic-gate-fail-open)"; assert_not_empty "detector present: systemic" "${RE}"
expect CATCH "${RE}" "the unhealthy branch **only logs** — the function **always returns 0**, so the gate never blocks a deploy even when a dependency is down."
expect CATCH "${RE}" "there's **no \`return 1\`** anywhere; an unhealthy dependency is logged but the deploy proceeds — the gate **fails open**."
expect CATCH "${RE}" "this **defeats the purpose** of the gate: \`check_one\` failure just logs, and control falls through to \`return 0\`."
expect CATCH "${RE}" "the gate is **vacuous** — every path leads to \`return 0\`; it can never block."
expect CATCH "${RE}" "\`check_one\` failure does not affect the return value, so an unhealthy dep never blocks the deploy."
expect CATCH "${RE}" "it logs the failure but should return 1 to block the deploy."
expect MISS  "${RE}" "the loop correctly skips blank lines and checks each dependency."
expect MISS  "${RE}" "consider logging the healthy dependencies too for visibility."
expect MISS  "${RE}" "\`check_one\` should probably have a timeout to avoid hanging."
expect MISS  "${RE}" "you might want to quote \`\$deps_file\` in the redirect."
expect MISS  "${RE}" "the comment says it blocks on unhealthy deps, which is a sensible gate design."
# Adversarial (code-review #3): NEUTRAL descriptions that restate the control
# flow — even approvingly — must NOT score as catching the fail-open. These
# matched the original 'only logs'/'just logs'/'logs but'/'does not block'
# branches, which were removed.
expect MISS  "${RE}" "The function only logs unhealthy dependencies and then returns 0 to allow the deploy."
expect MISS  "${RE}" "it just logs a message and returns 0 as designed"
expect MISS  "${RE}" "it logs it but continues to the next dependency"
expect MISS  "${RE}" "If a dep is unhealthy it logs but does not crash, which is good"

# --- layered-depth-promote-fail-open (depth beyond the first finding) ---
# The snippet has OBVIOUS decoys (unquoted $artifact) plus a DEEP fail-open (the
# gate trusts the absence of "FAIL", so a crashed/empty smoke log promotes a
# broken build). The detector measures ONLY the deep catch. Critically, a review
# that flags ONLY the decoys must MISS — that rejection is the discriminator.
echo "-- layered-depth-promote-fail-open --"
RE="$(det layered-depth-promote-fail-open)"; assert_not_empty "detector present: layered-depth" "${RE}"
expect CATCH "${RE}" "if \`run_smoke_tests\` crashes or writes no output, the log has no \`FAIL\`, so grep fails and the artifact is promoted — the gate fails open on a broken test run."
expect CATCH "${RE}" "this relies on the absence of a FAIL string; an empty or partial log (suite errored before running) passes the gate. Check the exit code instead."
expect CATCH "${RE}" "no FAIL doesn't mean the tests passed — if the smoke run never ran, the log is empty and \`grep -q FAIL\` returns false, so a broken build is promoted."
expect CATCH "${RE}" "the gate trusts that a missing FAIL means success; it should require an explicit PASS or check \`\$?\`."
expect CATCH "${RE}" "an empty log promotes the build; the smoke suite crashing is indistinguishable from passing."
# Keyword-free phrasings of the same insight (code-review #4 false-negative fix):
expect CATCH "${RE}" "the gate is green by default: anything other than a literal FAIL line is treated as a pass."
expect CATCH "${RE}" "no FAIL is treated as success even though the suite may never have run."
expect CATCH "${RE}" "if run_smoke_tests dies, the function returns 0 as if it passed."
# Decoy-only / unrelated / speculative-symptom — MUST MISS (the discriminator).
# code-review #4 caught the original bare `crash`/`empty`/`errors out` branches
# matching these without grasping that absence-of-FAIL is trusted as success.
expect MISS  "${RE}" "you should quote \`\$artifact\` — it's unquoted in several places and will break on spaces."
expect MISS  "${RE}" "the unquoted variable in \`[ -z \$artifact ]\` will error on empty input."
expect MISS  "${RE}" "the function runs smoke tests and returns 0 if there's no FAIL line."
expect MISS  "${RE}" "the unquoted \`\$artifact\` will break on spaces; also \`run_smoke_tests\` could crash if it's malformed."
expect MISS  "${RE}" "quote \`\$artifact\`; separately, if the log file errors out you won't see why."
expect MISS  "${RE}" "consider what happens if \`/tmp/smoke.log\` is an empty file from a prior run."
expect MISS  "${RE}" "add a timeout — \`run_smoke_tests\` could hang and the whole thing errors out before finishing."
expect MISS  "${RE}" "if the suite errors before running any test, you'll want a retry."

print_summary
