#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-evaluator-surface.sh ==="

# Protected-evaluator-surface advisory (selfpatch adoption, 2026-07-15 triage).
# A branch that edits the files defining what "verified" means (.verify.yml,
# the gate libs, the verdict writer, the gaming checker) can still record a
# clean verdict — self-referential evidence. The push gate must SURFACE that
# (advisory, never deny: deny variants backtested 56-94% false-block, 0
# catches / 108 PRs), and the gate-gaming check must see .verify.yml
# weakening. Three layers under test:
#   1. verdict.sh: _EVALUATOR_SURFACES list + diff_touches_evaluator predicate
#   2. openspec-guard.sh: advisory on push, emitted even outside SHIP phase
#   3. gate-gaming-check.sh: removed .verify.yml gate entries => suspect

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
VLIB="${PROJECT_ROOT}/hooks/lib/verdict.sh"
GGC="${PROJECT_ROOT}/skills/project-verification/scripts/gate-gaming-check.sh"
SSH_HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# ---------------------------------------------------------------------------
# 1. List consistency: _EVALUATOR_SURFACES must cover the drift-canary
#    manifest (openspec-guard.sh + _GATE_ENFORCE_LIBS) plus .verify.yml, so
#    growing the canary list without growing this one fails CI.
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
. "${VLIB}"

if [ -z "${_EVALUATOR_SURFACES:-}" ]; then
    _record_fail "verdict.sh defines _EVALUATOR_SURFACES" "variable empty/undefined after sourcing"
else
    _record_pass "verdict.sh defines _EVALUATOR_SURFACES"
fi

_canary_libs="$(sed -n 's/^_GATE_ENFORCE_LIBS="\(.*\)"$/\1/p' "${SSH_HOOK}" | head -1)"
if [ -z "${_canary_libs}" ]; then
    _record_fail "canary list extracted from session-start-hook" "no _GATE_ENFORCE_LIBS assignment found"
else
    _record_pass "canary list extracted from session-start-hook"
fi
for _f in hooks/openspec-guard.sh ${_canary_libs} .verify.yml; do
    case " ${_EVALUATOR_SURFACES:-} " in
        *" ${_f} "*) _record_pass "evaluator surfaces include ${_f}" ;;
        *)           _record_fail "evaluator surfaces include ${_f}" "missing from _EVALUATOR_SURFACES" ;;
    esac
done

# ---------------------------------------------------------------------------
# 2. diff_touches_evaluator predicate on a fixture repo
# ---------------------------------------------------------------------------
_bool() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }

TMP="$(mktemp -d /tmp/evalsurf-XXXXXX)"
REPO="${TMP}/repo"
mkdir -p "${REPO}"
(
  cd "${REPO}"
  git init -q
  git config user.email t@t; git config user.name t
  # Default branch may be main or master; _routing_base tries both.
  mkdir -p hooks/lib config
  printf 'substrate: local\nchecks:\n  - name: tests\n    run: true\n' > .verify.yml
  echo lib > hooks/lib/verdict.sh
  echo '{}' > config/default-triggers.json
  echo readme > README.md
  git add -A; git commit -qm c1
  git checkout -qb feat
)

# Branch == base (no commits yet): no advisory, fail-open silence.
if command -v diff_touches_evaluator >/dev/null 2>&1; then
    _record_pass "diff_touches_evaluator is defined"
else
    _record_fail "diff_touches_evaluator is defined" "function missing after sourcing verdict.sh"
fi
assert_equals "empty branch diff => no match" "1" "$(_bool diff_touches_evaluator "${REPO}")"

# Non-evaluator change only => no match.
( cd "${REPO}"; echo x >> README.md; git commit -qam readme )
assert_equals "README-only diff => no match"  "1" "$(_bool diff_touches_evaluator "${REPO}")"

# .verify.yml touched => match, and the matched path is printed.
( cd "${REPO}"; printf '# weakened\n' >> .verify.yml; git commit -qam weaken )
assert_equals ".verify.yml diff => match"     "0" "$(_bool diff_touches_evaluator "${REPO}")"
out="$(diff_touches_evaluator "${REPO}" 2>/dev/null || true)"
assert_contains ".verify.yml named in output" ".verify.yml" "${out:-<empty>}"

# Gate lib touched => match.
( cd "${REPO}"; echo x >> hooks/lib/verdict.sh; git commit -qam lib )
assert_equals "gate-lib diff => match"        "0" "$(_bool diff_touches_evaluator "${REPO}")"

# Exact-path discipline: a nested file that merely CONTAINS a surface name
# must not match (surfaces are files, not trees).
( cd "${REPO}"; git checkout -q "$(git rev-parse --verify main 2>/dev/null || git rev-parse --verify master)" ; git checkout -qb feat2
  mkdir -p docs; echo x > "docs/.verify.yml.md"; git add -A; git commit -qm docs )
assert_equals "lookalike path => no match"    "1" "$(_bool diff_touches_evaluator "${REPO}")"

# ---------------------------------------------------------------------------
# 3. Guard e2e: advisory on push, never deny, emitted outside SHIP phase.
#    ACSM_SKIP_PUSH_GATE=1 (human-set env) bypasses DENIALS; advisories must
#    still emit — that invariant is documented in the guard itself.
# ---------------------------------------------------------------------------
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/evalsurf-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"     # basename "t" -> token "session-t"

_mkinput() {
    jq -n --arg tp "$_TPATH" --arg cmd "${1:-git push origin HEAD}" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}
# cwd = fixture repo so the guard's git calls resolve against it. No SHIP
# signal file exists in this HOME => exercises the non-SHIP emission path.
run_guard_in() {
    local repo="$1" branch="$2"
    ( cd "${repo}" && git checkout -q "${branch}" && \
      _mkinput | ACSM_SKIP_PUSH_GATE=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null )
}

out="$(run_guard_in "${REPO}" "feat")"
assert_contains     "evaluator advisory emitted (non-SHIP push)" "EVALUATOR SURFACE"   "${out:-<empty>}"
assert_contains     "advisory names .verify.yml"                 ".verify.yml"         "${out:-<empty>}"
assert_contains     "advisory is additionalContext"              "additionalContext"   "${out:-<empty>}"
assert_not_contains "advisory never denies"                      '"deny"'              "${out:-}"

out="$(run_guard_in "${REPO}" "feat2")"
assert_not_contains "clean branch => no evaluator advisory"      "EVALUATOR SURFACE"   "${out:-}"

export HOME="$_OLDHOME"

# ---------------------------------------------------------------------------
# 4. gate-gaming-check.sh: .verify.yml gate-entry removal => suspect
# ---------------------------------------------------------------------------
_ggc() { printf '%s\n' "$1" | bash "${GGC}" 2>/dev/null; }

_weaken_diff='--- a/.verify.yml
+++ b/.verify.yml
@@ -1,6 +1,4 @@
 substrate: local
 checks:
-  - name: tests
-    run: bash tests/run-tests.sh
   - name: lint
     run: bash lint.sh'
out="$(_ggc "${_weaken_diff}")"
assert_contains "removed .verify.yml gate entry => suspect" "suspect" "${out:-<empty>}"
assert_contains "offending name: line quoted"               "name: tests" "${out:-<empty>}"

_grow_diff='--- a/.verify.yml
+++ b/.verify.yml
@@ -1,4 +1,6 @@
 substrate: local
 checks:
+  - name: lint
+    run: bash lint.sh
   - name: tests'
out="$(_ggc "${_grow_diff}")"
assert_contains ".verify.yml additions stay clean" "clean" "${out:-<empty>}"

# name:/run: removals OUTSIDE .verify.yml (e.g. a workflow step) must not hit,
# even when a .verify.yml hunk appears earlier in the same diff.
_decoy_diff='--- a/.verify.yml
+++ b/.verify.yml
@@ -1,3 +1,4 @@
 substrate: local
 checks:
+  - name: extra
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -10,8 +10,6 @@
     steps:
-      - name: old-step
-        run: echo hi
       - name: build'
out="$(_ggc "${_decoy_diff}")"
assert_contains "workflow name:/run: removals stay clean" "clean" "${out:-<empty>}"

# ---------------------------------------------------------------------------
# 5. Wiring: verify-and-record.sh feeds .verify.yml hunks to the checker
# ---------------------------------------------------------------------------
# Grep the diff invocation line only — the script mentions .verify.yml in
# other contexts (VY= path), which would pass this assertion vacuously.
var="$(grep -F -- '...HEAD --' "${PROJECT_ROOT}/scripts/verify-and-record.sh" || true)"
assert_contains "gate-gaming diff pathspec includes .verify.yml" ".verify.yml" "${var:-<empty>}"

rm -rf "${TMP}"
print_summary
exit $?
