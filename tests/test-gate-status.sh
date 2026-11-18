#!/usr/bin/env bash
# test-gate-status.sh — staleness-delta classifier + gate-status observer.
# Covers: docs/src classification, fail-open silence, the observational
# exit-0 invariant, guard decision-order replay against fixture evidence,
# and the --help ≈ docs/enforcement-map.md drift pin (constraint c).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

GATE_STATUS="${REPO_ROOT}/scripts/gate-status.sh"
CLASSIFIER="${REPO_ROOT}/hooks/lib/staleness-delta.sh"

echo "== syntax (bash 3.2) =="
/bin/bash -n "${CLASSIFIER}" && _record_pass "staleness-delta.sh parses under /bin/bash" \
    || _record_fail "staleness-delta.sh parses under /bin/bash" "syntax error"
/bin/bash -n "${GATE_STATUS}" && _record_pass "gate-status.sh parses under /bin/bash" \
    || _record_fail "gate-status.sh parses under /bin/bash" "syntax error"

# ---------------------------------------------------------------------------
# Fixture repo: main with a base commit, feature branch with a docs commit,
# a source commit, and a rename — run everything under an isolated HOME.
# setup_test_env points CLAUDE_PLUGIN_ROOT at the fake home; gate-status must
# resolve the REAL repo's libs, so pin it back.
# ---------------------------------------------------------------------------
setup_test_env
export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"
FIX="${TEST_TMPDIR}/fixrepo"
mkdir -p "${FIX}" && cd "${FIX}" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
# macOS: mktemp yields /var/... but git resolves /private/var/... — the branch
# ledger keys on the resolved path, so use it everywhere.
FIX="$(git rev-parse --show-toplevel)"
mkdir -p docs hooks
echo base > docs/a.md && echo base > hooks/a.sh
git add . && git commit -qm base
git checkout -qb feat
REVIEW_SHA="$(git rev-parse HEAD)"
printf 'l1\nl2\n' >> docs/a.md && echo note > openspec-note.md
git add . && git commit -qm "docs commit"
printf 's1\ns2\ns3\n' >> hooks/a.sh
git add . && git commit -qm "src commit"
git mv docs/a.md docs/b.md && git commit -qm "rename docs"
HEAD_SHA="$(git rev-parse HEAD)"

echo "== staleness_delta classifier =="
. "${CLASSIFIER}"
out="$(staleness_delta "${REVIEW_SHA}" "${HEAD_SHA}" "${FIX}")"
# Endpoint diff: docs/a.md deleted (1 line at REVIEW_SHA) + docs/b.md added (3)
# + openspec-note.md (1) = 3 docs files, 5 lines; hooks/a.sh = 1 src file, 3 lines
assert_equals "classifier splits docs vs src, rename counted as literal add+delete" \
    "files=4 docs_files=3 src_files=1 docs_lines=5 src_lines=3" "${out}"
assert_equals "empty delta is all zeros" \
    "files=0 docs_files=0 src_files=0 docs_lines=0 src_lines=0" \
    "$(staleness_delta "${HEAD_SHA}" "${HEAD_SHA}" "${FIX}")"
assert_equals "unknown from-sha is silent (fail-open)" "" "$(staleness_delta deadbeef "${HEAD_SHA}" "${FIX}")"
# contract pin, not red-first: a bad to-sha was already silent via git-diff
# fail-open; the explicit guard makes the from/to contract symmetric.
assert_equals "unknown to-sha is silent (fail-open)" "" "$(staleness_delta "${REVIEW_SHA}" deadbeef "${FIX}")"
assert_equals "empty from-sha is silent (fail-open)" "" "$(staleness_delta "" "${HEAD_SHA}" "${FIX}")"
rc=0; staleness_delta deadbeef "${HEAD_SHA}" "${FIX}" >/dev/null || rc=$?
assert_equals "fail-open returns 0" "0" "${rc}"

echo "== gate-status: observational exit-0 invariant =="
out="$(cd "${FIX}" && /bin/bash "${GATE_STATUS}")"; rc=$?
assert_equals "exit 0 with zero evidence" "0" "${rc}"
assert_contains "no evidence => global gate would deny" "WOULD DENY at 5 global fail-closed gate" "${out}"
assert_contains "names both missing milestones" "requesting-code-review and verification-before-completion" "${out}"
assert_contains "fixture is not a routing repo" "n/a (not a routing repo" "${out}"
out="$(cd "${TEST_TMPDIR}" && /bin/bash "${GATE_STATUS}")"; rc=$?
assert_equals "exit 0 outside a git repo" "0" "${rc}"
assert_contains "non-repo case explained" "not a git repository" "${out}"
/bin/bash "${GATE_STATUS}" --help >/dev/null; rc=$?
assert_equals "--help exits 0" "0" "${rc}"

echo "== gate-status: evidence flips the replay (guard order) =="
# Record both milestones in the branch ledger via the guard's OWN lib.
. "${REPO_ROOT}/hooks/lib/branch-ledger.sh"
( cd "${FIX}" && branch_ledger_record "requesting-code-review" "${FIX}" \
    && branch_ledger_record "verification-before-completion" "${FIX}" )
out="$(cd "${FIX}" && /bin/bash "${GATE_STATUS}")"
assert_contains "ledger evidence => would allow (non-routing repo)" "=> git push NOW: WOULD ALLOW" "${out}"
assert_contains "allow summary carries concurrency caveat when chain gates unevaluated" \
    "caveat: chain gates 2-4 were unevaluated" "${out}"
assert_contains "review evidence line shows ledger source" ": ledger @" "${out}"
assert_contains "review at HEAD => no staleness" "review recorded at HEAD — no post-review delta" "${out}"
assert_equals "replay lists gates 1-6 in guard order" \
    "1mutate-then-push2chain3chain4verify-hardening5global6routing" \
    "$(printf '%s\n' "${out}" | awk '/^  [1-6] /{printf "%s%s", $1, $2}')"

echo "== gate-status: staleness observation line =="
( cd "${FIX}" && echo post >> hooks/a.sh && git add . && git commit -qm "post-review src" )
out="$(cd "${FIX}" && /bin/bash "${GATE_STATUS}")"
assert_contains "staleness line uses the shared classifier output" \
    "post-review delta to HEAD: files=1 docs_files=0 src_files=1 docs_lines=0 src_lines=1" "${out}"
assert_contains "staleness framed as observation, not a gate" "observation only" "${out}"
assert_contains "ledger sha flagged as not HEAD after new commit" "(not HEAD)" "${out}"

echo "== gate-status: routing governance + verdict layers =="
# Make it a routing repo; the branch diff (merge-base main..HEAD) already touches hooks/.
mkdir -p "${FIX}/config" && echo '{}' > "${FIX}/config/default-triggers.json"
( cd "${FIX}" && git add config && git commit -qm "feat: routing repo marker" )
out="$(cd "${FIX}" && /bin/bash "${GATE_STATUS}")"
assert_contains "routing surface detected" "routing repo: true; branch diff touches skills/|config/|hooks/: true" "${out}"
assert_contains "no verdict => routing gate would deny" "WOULD DENY at 6 routing governance" "${out}"

# Clean verdict at HEAD under the singleton token => routing gate passes.
printf 'session-testtoken' > "${TEST_HOME}/.claude/.skill-session-token"
FIX_HEAD="$(cd "${FIX}" && git rev-parse HEAD)"
printf '{"sha":"%s","failed":[],"could_not_verify":[],"passed":["tests"],"gate_gaming_status":"clean"}\n' "${FIX_HEAD}" \
    > "${TEST_HOME}/.claude/.skill-project-verified-session-testtoken"
out="$(cd "${FIX}" && /bin/bash "${GATE_STATUS}")"
assert_contains "clean verdict at HEAD passes routing gate" "pass (clean verdict at HEAD)" "${out}"
assert_contains "all gates pass with ledger + clean verdict" "=> git push NOW: WOULD ALLOW" "${out}"

# G1 (#295): the same record with no reported check is not clean, and the
# replay prints the remedy the guard's deny carries. The cell above is the
# control: it differs by the `passed` field alone.
printf '{"sha":"%s","gate_gaming_status":"clean"}\n' "${FIX_HEAD}" \
    > "${TEST_HOME}/.claude/.skill-project-verified-session-testtoken"
out="$(cd "${FIX}" && /bin/bash "${GATE_STATUS}")"
assert_contains "G1 a verdict with no reported check: routing gate would deny" "WOULD DENY (the verdict at HEAD is not clean)" "${out}"
assert_contains "G1 ...and the replay says why" "reports no check" "${out}"
assert_contains "G1 ...and the evidence line names that state" "no reported check" "${out}"

# Failing verdict at HEAD + verify in an active chain => gate 4 denies first.
printf '{"sha":"%s","failed":["tests/run-tests.sh"],"could_not_verify":[],"gate_gaming_status":"clean"}\n' "${FIX_HEAD}" \
    > "${TEST_HOME}/.claude/.skill-project-verified-session-testtoken"
printf '{"chain":["requesting-code-review","verification-before-completion"],"completed":["requesting-code-review","verification-before-completion"]}\n' \
    > "${TEST_HOME}/.claude/.skill-composition-state-session-testtoken"
out="$(cd "${FIX}" && /bin/bash "${GATE_STATUS}")"
assert_contains "failing verdict at HEAD denies at gate 4 before 5/6" "WOULD DENY at 4 verify-hardening" "${out}"
assert_contains "verdict evidence names the failing gate" "FAILED (gates: tests/run-tests.sh)" "${out}"
rc=0; (cd "${FIX}" && /bin/bash "${GATE_STATUS}" >/dev/null) || rc=$?
assert_equals "exit 0 even when every gate would deny" "0" "${rc}"

echo "== help ≈ enforcement-map drift pin (constraint c) =="
help_out="$(/bin/bash "${GATE_STATUS}" --help)"
map="$(cat "${REPO_ROOT}/docs/enforcement-map.md")"
for phrase in "mutate-then-push" "global fail-closed gate" "routing governance" \
              "ACSM_SKIP_PUSH_GATE=1" "ADVISORY BY DESIGN" "gh pr merge"; do
    assert_contains "--help mentions: ${phrase}" "${phrase}" "${help_out}"
    assert_contains "enforcement-map mentions: ${phrase}" "${phrase}" "${map}"
done
assert_contains "--help points to the map" "docs/enforcement-map.md" "${help_out}"
assert_contains "map points to gate-status.sh" "scripts/gate-status.sh" "${map}"
# The guard must still contain the six gate concepts the replay claims to
# mirror (coarse anti-drift anchor: renaming/removing one breaks this pin).
guard="$(cat "${REPO_ROOT}/hooks/openspec-guard.sh")"
for anchor in "command_git_mutate_before_push" "Check 1: REVIEW" "Check 2: VERIFY" \
              "verdict_sha_is_head" "Global fail-closed gate" "Routing-governance gate"; do
    assert_contains "guard still contains replayed concept: ${anchor}" "${anchor}" "${guard}"
done
# gate-status renders the verdict sha via verdict.sh's internal _verdict_sha —
# anchor the helper so a rename doesn't silently blank the display (fail-open
# hides it from every behavioral assert).
assert_contains "verdict.sh still defines _verdict_sha (rendered by gate-status)" \
    "_verdict_sha()" "$(cat "${REPO_ROOT}/hooks/lib/verdict.sh")"

echo "== enforcement-map names every hook that can block (#424) =="
# The map claims to list everything that can block. Until #424 it listed the
# push gate alone while three other hooks denied, and nothing failed. The
# population is DERIVED from hooks/: any top-level hook with a line emitting
# "permissionDecision" as deny (the matcher tests/test-deny-reason-reaches-model.sh
# uses, with the same known limit: a deny built from a variable is not seen),
# or a {"decision":"block"} (none today), plus any hook that exits 2. Floors
# keep it from passing on an empty match.
# NOT covered, and stated in the map rather than hidden: a second deny branch
# added to a hook already listed (only the push gate's are enumerated, by
# label, below), and a refusal added to a script under scripts/.
# The glob is the right population only while every registered hook command is
# a top-level hooks/*.sh file, so that is asserted first.
reg_cmds="$(jq -r '.hooks[][] | .hooks[].command' "${REPO_ROOT}/hooks/hooks.json" 2>/dev/null | sort -u)"
n_reg="$(printf '%s\n' "${reg_cmds}" | grep -c '.' || true)"
if [ "${n_reg:-0}" -ge 20 ]; then
    _record_pass "hook registrations read from hooks.json (${n_reg}, floor 20)"
else
    _record_fail "hook registrations read from hooks.json" "found ${n_reg}, expected >= 20"
fi
while IFS= read -r reg; do
    [ -n "${reg}" ] || continue
    reg_file="${reg%% *}"
    # Commands quote the plugin-root path (tests/test-hook-file-modes.sh).
    reg_file="${reg_file#\"}"; reg_file="${reg_file%\"}"
    case "${reg_file}" in
        '${CLAUDE_PLUGIN_ROOT}/hooks/'*/*|'${CLAUDE_PLUGIN_ROOT}/hooks/'*[!h]|'${CLAUDE_PLUGIN_ROOT}/hooks/'*[!s]h)
            _record_fail "registered hook is a top-level hooks/*.sh: ${reg_file}" \
                "the blocking-hook scan globs hooks/*.sh and cannot see this one" ;;
        '${CLAUDE_PLUGIN_ROOT}/hooks/'*.sh)
            _record_pass "registered hook is a top-level hooks/*.sh: ${reg_file##*/}" ;;
        *)
            _record_fail "registered hook is a top-level hooks/*.sh: ${reg_file}" \
                "the blocking-hook scan globs hooks/*.sh and cannot see this one" ;;
    esac
done <<EOF
${reg_cmds}
EOF
# Widened after review: the quotes may be escaped (a printf inside double
# quotes), `"continue":false` also stops, and `exit 2` need not start the line
# (`|| exit 2`, `{ …; exit 2; }`).
deny_hooks="$(grep -lE '\\?"permissionDecision\\?"[^#]*deny|\\?"decision\\?"[^#]*block|\\?"continue\\?"[^#]*false' "${REPO_ROOT}"/hooks/*.sh 2>/dev/null || true)"
exit2_hooks="$(grep -lE '(^|[;&|{[:space:]])exit 2([[:space:];}]|$)' "${REPO_ROOT}"/hooks/*.sh 2>/dev/null || true)"
# A blocking hook must be named in the part of the map that describes blocks,
# not merely somewhere on the page: a hook listed under "Advisory only" that
# later starts denying would otherwise pass.
map_blocks="$(awk '/^## Hard blocks/{p=1} /^## Advisory only/{p=0} p' "${REPO_ROOT}/docs/enforcement-map.md")"
# The END heading must exist too: without it awk reads to the end of the file
# and the advisory section counts as a blocks section again.
if [ -n "${map_blocks}" ] && grep -q '^## Advisory only' "${REPO_ROOT}/docs/enforcement-map.md"; then
    _record_pass "map's blocks sections extracted"
else
    _record_fail "map's blocks sections extracted" "no text between '## Hard blocks' and '## Advisory only' — the headings moved"
fi
n_deny_hooks="$(printf '%s\n' "${deny_hooks}" | grep -c '.' || true)"
n_exit2_hooks="$(printf '%s\n' "${exit2_hooks}" | grep -c '.' || true)"
if [ "${n_deny_hooks:-0}" -ge 4 ] && [ "${n_exit2_hooks:-0}" -ge 1 ]; then
    _record_pass "blocking-hook population is non-vacuous (${n_deny_hooks} deny, ${n_exit2_hooks} exit-2)"
else
    _record_fail "blocking-hook population is non-vacuous" \
        "found ${n_deny_hooks} deny-emitting and ${n_exit2_hooks} exit-2 hooks, expected >= 4 and >= 1"
fi
while IFS= read -r hook_path; do
    [ -n "${hook_path}" ] || continue
    assert_contains "enforcement-map names blocking hook: ${hook_path##*/}" "hooks/${hook_path##*/}" "${map_blocks}"
done <<EOF
${deny_hooks}
${exit2_hooks}
EOF
# Every push-gate deny label the guard can record is in the map too: the
# phase-enforcement leg was a seventh deny site the six-row table never showed.
deny_labels="$(grep -o '_DECISION="deny:[a-z-]*"' "${REPO_ROOT}/hooks/openspec-guard.sh" \
               | sed -e 's/^_DECISION="deny://' -e 's/"$//' | sort -u)"
n_labels="$(printf '%s\n' "${deny_labels}" | grep -c '.' || true)"
if [ "${n_labels:-0}" -ge 7 ]; then
    _record_pass "push-gate deny labels found (${n_labels}, floor 7)"
else
    _record_fail "push-gate deny labels found" "found ${n_labels}, expected >= 7 — the label idiom moved"
fi
while IFS= read -r label; do
    [ -n "${label}" ] || continue
    assert_contains "enforcement-map names push-gate deny label: ${label}" "\`${label}\`" "${map_blocks}"
done <<EOF
${deny_labels}
EOF
# The other direction: a hook the map names must exist, or the map points at
# a file that was renamed away.
map_hooks="$(grep -o 'hooks/[a-z-]*\.sh' "${REPO_ROOT}/docs/enforcement-map.md" | sort -u)"
while IFS= read -r named; do
    [ -n "${named}" ] || continue
    if [ -f "${REPO_ROOT}/${named}" ]; then
        _record_pass "hook named in the map exists: ${named}"
    else
        _record_fail "hook named in the map exists: ${named}" "no such file"
    fi
done <<EOF
${map_hooks}
EOF
assert_contains "--help says it replays the push gate only" "replays the push gate only" "${help_out}"

cd "${REPO_ROOT}" || true
teardown_test_env
print_summary
