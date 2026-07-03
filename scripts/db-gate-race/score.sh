#!/bin/bash
# score.sh — deterministic scorer + FROZEN decision rule for the db-gate-race.
#
# Aggregates per-arm detection & false-positive rates from the variance
# reports written by tests/run-behavioral-evals.sh (one *-variance.md per
# (arm, scenario) under tests/artifacts/db-gate-race/<arm>/), applies the
# frozen decision rule, and writes a scratch DECISION file (default
# docs/plans/db-gate-race-DECISION.md, override with DECISION_OUT). NOTE: the
# AUTHORITATIVE, committed record is openspec/changes/db-gate-decision-race/
# DECISION.md — this scratch output is not that file; copy it there when
# finalizing a re-run.
#
# Usage:
#   . scripts/db-gate-race/score.sh --lib   # source decide()/aggregate_arm() only
#   bash scripts/db-gate-race/score.sh      # run full aggregation + decision
#
# Bash 3.2 compatible (macOS /bin/bash). No `set -e`.

# -------- Frozen decision rule (do NOT change post-hoc; see design.md) --------
DET_MARGIN="0.20"   # variant must beat A0 detection by >= 20pp
FP_CEIL="0.10"      # variant false-positive must be <= 10pp (INCLUSIVE)
TIE="0.10"          # |score(B1)-score(B2)| < 10pp => point-don't-own tiebreak

# -------- float helpers (awk; no bc dependency) --------
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }   # a >= b
le() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<=b)}'; }   # a <= b
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<b)}'; }    # a <  b
score() { awk -v d="$1" -v f="$2" 'BEGIN{printf "%.4f", d-f}'; }

# decide detA0 fpA0 detB1 fpB1 detB2 fpB2 -> prints one of:
#   ship-B2 | ship-B1 | park
decide() {
    local dA="$1" fA="$2" dB1="$3" fB1="$4" dB2="$5" fB2="$6"
    local sB1 sB2 gapB1 gapB2 b1_ok b2_ok

    sB1="$(score "$dB1" "$fB1")"
    sB2="$(score "$dB2" "$fB2")"
    gapB1="$(awk -v x="$dB1" -v y="$dA" 'BEGIN{printf "%.4f", x-y}')"
    gapB2="$(awk -v x="$dB2" -v y="$dA" 'BEGIN{printf "%.4f", x-y}')"

    b1_ok=0
    b2_ok=0
    # "clears the bar": gap >= DET_MARGIN AND fp <= FP_CEIL (inclusive).
    if ge "$gapB1" "$DET_MARGIN" && le "$fB1" "$FP_CEIL"; then b1_ok=1; fi
    if ge "$gapB2" "$DET_MARGIN" && le "$fB2" "$FP_CEIL"; then b2_ok=1; fi

    if [ "$b1_ok" -eq 0 ] && [ "$b2_ok" -eq 0 ]; then
        echo "park"
        return
    fi

    if [ "$b1_ok" -eq 1 ] && [ "$b2_ok" -eq 1 ]; then
        local diff
        diff="$(awk -v a="$sB1" -v b="$sB2" 'BEGIN{d=a-b; if(d<0)d=-d; printf "%.4f", d}')"
        if lt "$diff" "$TIE"; then
            echo "ship-B1"   # point-don't-own tiebreak
            return
        fi
        if ge "$sB2" "$sB1"; then echo "ship-B2"; else echo "ship-B1"; fi
        return
    fi

    if [ "$b2_ok" -eq 1 ]; then echo "ship-B2"; else echo "ship-B1"; fi
}

# -------- aggregation: parse *-variance.md reports for one arm dir --------
#
# Partitions by scenario id prefix (filename prefix mirrors the scenario id):
#   defect-*  -> "text" assertions; detection contribution per row = Pass/(Pass+Fail)
#   clean-*   -> "absent" assertions; fp contribution per row = Fail/(Pass+Fail)
#     (the runner records Pass = "no false flag" / Fail = "false flag raised"
#      for absent assertions, so Fail is the false-positive event)
#
# Per-assertion rows are lines matching '^\| [0-9]' inside a report:
#   | # | Description | Pass | Fail | Pass rate | Classification |
# We only trust the Pass/Fail integer columns (3rd/4th pipe-delimited field)
# and recompute rates ourselves — never trust the report's rendered
# "Pass rate"/"Classification" text columns (rounding, drift).
#
# aggregate_arm <arm_dir>
# prints: detection_rate<TAB>false_positive_rate<TAB>n_defect_assertions<TAB>n_clean_assertions
aggregate_arm() {
    local arm_dir="$1"
    local f base sid kind

    local det_sum="0" det_n="0" fp_sum="0" fp_n="0"

    if [ ! -d "$arm_dir" ]; then
        printf '0\t0\t0\t0\n'
        return
    fi

    for f in "$arm_dir"/*-variance.md; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        sid="${base%-variance.md}"
        case "$sid" in
            defect-*) kind="detect" ;;
            clean-*)  kind="clean" ;;
            *)        kind="" ;;
        esac
        [ -n "$kind" ] || continue

        # Extract Pass/Fail integer pairs from assertion rows ("| N | ... |").
        # awk emits "pass fail" per matching row.
        local pairs
        pairs="$(awk -F'|' '/^\| *[0-9]+ *\|/ {
            gsub(/^[ \t]+|[ \t]+$/, "", $4); gsub(/^[ \t]+|[ \t]+$/, "", $5);
            print $4, $5
        }' "$f")"

        [ -n "$pairs" ] || continue

        while IFS=' ' read -r p flag; do
            [ -n "$p" ] || continue
            local total contrib
            total=$((p + flag))
            [ "$total" -gt 0 ] || continue
            if [ "$kind" = "detect" ]; then
                contrib="$(awk -v p="$p" -v t="$total" 'BEGIN{printf "%.6f", p/t}')"
                det_sum="$(awk -v a="$det_sum" -v b="$contrib" 'BEGIN{printf "%.6f", a+b}')"
                det_n=$((det_n + 1))
            else
                contrib="$(awk -v flag="$flag" -v t="$total" 'BEGIN{printf "%.6f", flag/t}')"
                fp_sum="$(awk -v a="$fp_sum" -v b="$contrib" 'BEGIN{printf "%.6f", a+b}')"
                fp_n=$((fp_n + 1))
            fi
        done <<EOF_PAIRS
$pairs
EOF_PAIRS
    done

    local det_rate fp_rate
    if [ "$det_n" -gt 0 ]; then
        det_rate="$(awk -v s="$det_sum" -v n="$det_n" 'BEGIN{printf "%.4f", s/n}')"
    else
        det_rate="0.0000"
    fi
    if [ "$fp_n" -gt 0 ]; then
        fp_rate="$(awk -v s="$fp_sum" -v n="$fp_n" 'BEGIN{printf "%.4f", s/n}')"
    else
        fp_rate="0.0000"
    fi

    printf '%s\t%s\t%s\t%s\n' "$det_rate" "$fp_rate" "$det_n" "$fp_n"
}

# Allow the test suite to source decide()/aggregate_arm() without running main.
[ "${1:-}" = "--lib" ] && return 0 2>/dev/null

# -------- main --------
main() {
    local out_dir="tests/artifacts/db-gate-race"
    # Scratch output, not the committed record. Non-date-stamped so a revival
    # re-run doesn't resurrect a stale 2026-07-01 filename; override via DECISION_OUT.
    # Authoritative committed record: openspec/changes/db-gate-decision-race/DECISION.md.
    local decision_file="${DECISION_OUT:-docs/plans/db-gate-race-DECISION.md}"
    local arm result

    if [ ! -d "$out_dir" ]; then
        echo "no artifacts yet — run Task 6/7 first (missing ${out_dir})"
        exit 0
    fi

    local any_reports="0"
    for arm in A0 B1 B2; do
        if [ -d "${out_dir}/${arm}" ] && ls "${out_dir}/${arm}"/*-variance.md >/dev/null 2>&1; then
            any_reports="1"
        fi
    done
    if [ "$any_reports" = "0" ]; then
        echo "no artifacts yet — run Task 6/7 first (no *-variance.md reports under ${out_dir})"
        exit 0
    fi

    local detA0 fpA0 nDefA0 nClnA0
    local detB1 fpB1 nDefB1 nClnB1
    local detB2 fpB2 nDefB2 nClnB2

    result="$(aggregate_arm "${out_dir}/A0")"
    IFS="$(printf '\t')" read -r detA0 fpA0 nDefA0 nClnA0 <<EOF_A0
$result
EOF_A0

    result="$(aggregate_arm "${out_dir}/B1")"
    IFS="$(printf '\t')" read -r detB1 fpB1 nDefB1 nClnB1 <<EOF_B1
$result
EOF_B1

    result="$(aggregate_arm "${out_dir}/B2")"
    IFS="$(printf '\t')" read -r detB2 fpB2 nDefB2 nClnB2 <<EOF_B2
$result
EOF_B2

    local scoreA0 scoreB1 scoreB2
    scoreA0="$(score "$detA0" "$fpA0")"
    scoreB1="$(score "$detB1" "$fpB1")"
    scoreB2="$(score "$detB2" "$fpB2")"

    local verdict
    verdict="$(decide "$detA0" "$fpA0" "$detB1" "$fpB1" "$detB2" "$fpB2")"

    # Safety-stop note: a full statistical overlap test (e.g. CI overlap
    # between arms) is NOT computed here — out of scope for this task. As a
    # cheap spread indicator for the human, we report the raw n (assertion
    # count) per arm; wide disparities in n across arms are a signal the
    # rates aren't comparable yet. The verdict token + rates are the
    # deliverable; the human/controller applies the safety-stop judgment.

    mkdir -p "$(dirname "$decision_file")"
    {
        echo "# db-gate-race — Decision"
        echo ""
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "## Per-arm results"
        echo ""
        echo "| arm | detection_rate | false_positive_rate | score | n_defect_assertions | n_clean_assertions |"
        echo "|---|---|---|---|---|---|"
        printf '| A0 | %s | %s | %s | %s | %s |\n' "$detA0" "$fpA0" "$scoreA0" "$nDefA0" "$nClnA0"
        printf '| B1 | %s | %s | %s | %s | %s |\n' "$detB1" "$fpB1" "$scoreB1" "$nDefB1" "$nClnB1"
        printf '| B2 | %s | %s | %s | %s | %s |\n' "$detB2" "$fpB2" "$scoreB2" "$nDefB2" "$nClnB2"
        echo ""
        echo "score(v) = detection_rate(v) - false_positive_rate(v)."
        echo ""
        echo "## Frozen decision rule"
        echo ""
        echo "- DET_MARGIN = ${DET_MARGIN} (variant must beat A0 detection by >= 20pp)"
        echo "- FP_CEIL = ${FP_CEIL} (variant false-positive must be <= 10pp, INCLUSIVE)"
        echo "- TIE = ${TIE} (|score(B1)-score(B2)| < 10pp => point-don't-own tiebreak => ship-B1)"
        echo "- A variant \"clears the bar\" iff (det_variant - det_A0) >= DET_MARGIN AND fp_variant <= FP_CEIL."
        echo "- If neither B1 nor B2 clears -> park."
        echo "- If exactly one clears -> ship that one."
        echo "- If both clear: ship-B1 if |score(B1)-score(B2)| < TIE, else ship whichever score is higher."
        echo ""
        echo "## Safety-stop note"
        echo ""
        echo "A full statistical overlap test between arms is out of scope for this"
        echo "deterministic scorer. The n_defect_assertions / n_clean_assertions"
        echo "columns above are a cheap spread indicator only (sample size per arm)."
        echo "The human/controller applies the safety-stop judgment before acting on"
        echo "the verdict below."
        echo ""
        echo "## Verdict"
        echo ""
        echo "\`${verdict}\`"
    } > "$decision_file"

    echo "=== db-gate-race decision ==="
    echo "A0: det=${detA0} fp=${fpA0} score=${scoreA0} (n_defect=${nDefA0} n_clean=${nClnA0})"
    echo "B1: det=${detB1} fp=${fpB1} score=${scoreB1} (n_defect=${nDefB1} n_clean=${nClnB1})"
    echo "B2: det=${detB2} fp=${fpB2} score=${scoreB2} (n_defect=${nDefB2} n_clean=${nClnB2})"
    echo "verdict: ${verdict}"
    echo "decision written to: ${decision_file}"
}

main "$@"
