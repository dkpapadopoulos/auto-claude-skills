#!/bin/bash
# backtest-evaluator-surface.sh — re-runnable calibration for the
# evaluator-surface advisory + .verify.yml gate-gaming rule (PR #116).
# Read-only against the repo; attack fixtures are built in mktemp dirs.
#
#   history [N]  Replay the last N first-parent commits on origin/main
#                (default 120; version bumps excluded): how often would the
#                EVALUATOR SURFACE advisory have fired, and how often would
#                gate-gaming (all rules / the .verify.yml rule alone) have
#                flagged suspect? Measures NOISE on real history.
#   attacks      Run the gate-weakening attack matrix in a fixture repo:
#                per attack class, does gate-gaming flag suspect and/or does
#                the advisory predicate fire? Measures CATCH-RATE, including
#                the documented design limits (run:-rewrite is gate-gaming
#                clean by entry-removal semantics; a clean-predicate lib edit
#                is advisory-only). Baseline 2026-07-16: 7/7 classes surfaced
#                by at least one layer.
#
# Detector versions under test come from origin/main (what is actually
# shipped), not the working tree. Bash 3.2.
set -u

MODE="${1:-history}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 1; }
GGC_TMP="$(mktemp "${TMPDIR:-/tmp}/ggc-main.XXXXXX")" || exit 1
VLIB_TMP="$(mktemp "${TMPDIR:-/tmp}/verdict-main.XXXXXX")" || exit 1
trap 'rm -f "$GGC_TMP" "$VLIB_TMP"' EXIT
git -C "$ROOT" show origin/main:skills/project-verification/scripts/gate-gaming-check.sh > "$GGC_TMP" || exit 1
git -C "$ROOT" show origin/main:hooks/lib/verdict.sh > "$VLIB_TMP" || exit 1
SURFACES="$(sed -n 's/^_EVALUATOR_SURFACES="\(.*\)"$/\1/p' "$VLIB_TMP")"
[ -n "$SURFACES" ] || { echo "no _EVALUATOR_SURFACES on origin/main" >&2; exit 1; }

_advisory_hits() { # stdin: name-only diff -> prints matched surfaces
    awk -v s=" ${SURFACES} " '$0 != "" && index(s, " " $0 " ")'
}

if [ "$MODE" = "history" ]; then
    N="${2:-120}"
    adv=0; sus_all=0; sus_vy=0; total=0
    adv_prs=""; sus_prs=""; sus_vy_prs=""
    while read -r sha subj; do
        case "$subj" in "chore: bump version"*) continue ;; esac
        total=$((total+1))
        hit="$(git -C "$ROOT" diff --name-only "${sha}^" "$sha" 2>/dev/null | _advisory_hits | tr '\n' ' ')"
        if [ -n "$hit" ]; then adv=$((adv+1)); adv_prs="${adv_prs}
  ${sha%${sha#???????}} [${hit% }] ${subj}"; fi
        out="$(git -C "$ROOT" -c diff.mnemonicPrefix=false diff "${sha}^" "$sha" -- '*test*' '*spec*' '.verify.yml' 2>/dev/null | bash "$GGC_TMP" 2>/dev/null | head -1)"
        case "$out" in suspect*) sus_all=$((sus_all+1)); sus_prs="${sus_prs}
  ${sha%${sha#???????}} ${subj}" ;; esac
        outv="$(git -C "$ROOT" -c diff.mnemonicPrefix=false diff "${sha}^" "$sha" -- '.verify.yml' 2>/dev/null | bash "$GGC_TMP" 2>/dev/null | head -1)"
        case "$outv" in suspect*) sus_vy=$((sus_vy+1)); sus_vy_prs="${sus_vy_prs}
  ${sha%${sha#???????}} ${subj}" ;; esac
    done <<EOF
$(git -C "$ROOT" log origin/main --first-parent -n "$N" --format='%H %s')
EOF
    echo "=== history backtest: ${total} first-parent commits (version bumps excluded) ==="
    echo "EVALUATOR SURFACE advisory fires: ${adv}/${total}${adv_prs}"
    echo ""
    echo "gate-gaming suspect (all rules): ${sus_all}/${total}${sus_prs}"
    echo ""
    echo ".verify.yml rule alone:          ${sus_vy}/${total}${sus_vy_prs}"
    exit 0
fi

if [ "$MODE" = "attacks" ]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/evalsurf-attacks.XXXXXX")" || exit 1
    trap 'rm -rf "$WORK"; rm -f "$GGC_TMP" "$VLIB_TMP"' EXIT
    cd "$WORK" || exit 1
    git -c init.defaultBranch=main init -q repo && cd repo
    git config user.email t@t; git config user.name t
    printf 'substrate: local\nchecks:\n  - name: tests\n    run: bash tests/run.sh\n  - name: lint\n    run: bash lint.sh\n' > .verify.yml
    mkdir -p tests hooks/lib
    printf 'assert_equals "a" "a"\nassertTrue x\n' > tests/test-core.sh
    echo lib > hooks/lib/verdict.sh
    git add -A && git commit -qm base

    atk() {
        local name="$1"; shift
        git checkout -q main && git checkout -qB "atk" && "$@" >/dev/null 2>&1
        git add -A >/dev/null 2>&1 && git commit -qm "$name" >/dev/null 2>&1
        local gg adv
        gg="$(git -c diff.mnemonicPrefix=false diff main..HEAD -- '*test*' '*spec*' '.verify.yml' | bash "$GGC_TMP" 2>/dev/null | head -1)"
        adv="$(git diff --name-only main HEAD | _advisory_hits | head -1)"
        if [ -n "$adv" ]; then adv="FIRES (${adv})"; else adv="silent"; fi
        printf '%-28s gate-gaming=%-8s advisory=%s\n' "$name" "$gg" "$adv"
    }
    # sed -i is BSD-vs-GNU divergent; use portable in-place-via-temp edits.
    _sed() { sed "$1" "$2" > "$2.n" && mv "$2.n" "$2"; }
    a_delete()   { git rm -q .verify.yml; }
    a_remove()   { printf 'substrate: local\nchecks:\n  - name: lint\n    run: bash lint.sh\n' > .verify.yml; }
    a_noop()     { _sed 's|run: bash tests/run.sh|run: true|' .verify.yml; }
    a_rename()   { _sed 's|name: tests|name: renamed-gate|' .verify.yml; }
    a_deassert() { printf '# emptied\n' > tests/test-core.sh; }
    a_skip()     { printf '@pytest.mark.skip\n' >> tests/test-core.sh; }
    a_predlib()  { echo "return 0 # always clean" >> hooks/lib/verdict.sh; }

    echo "=== attack matrix (detectors from origin/main) ==="
    atk "delete-.verify.yml"        a_delete
    atk "remove-gate-entry"         a_remove
    atk "rewrite-run-to-noop"       a_noop      # documented gate-gaming limit
    atk "rename-gate-entry"         a_rename
    atk "remove-test-assertions"    a_deassert  # pre-existing rule; advisory silent by design
    atk "add-skip-marker"           a_skip      # pre-existing rule; advisory silent by design
    atk "edit-clean-predicate-lib"  a_predlib   # advisory-only catch by design
    echo ""
    echo "Expected baseline: every class surfaced by >=1 layer; rewrite-run-to-noop"
    echo "is gate-gaming clean (entry-removal semantics) and advisory-covered."
    exit 0
fi

echo "usage: $0 [history [N] | attacks]" >&2
exit 2
