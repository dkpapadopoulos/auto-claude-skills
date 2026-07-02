#!/bin/bash
# test-score.sh — unit tests for scripts/db-gate-race/score.sh
#
# Part A: feeds synthetic per-arm rates into score.sh's decide() function
# (sourced as a library, main not executed) and checks the frozen-rule
# verdicts, including the inclusive fp<=0.10 ceiling boundary.
#
# Part B: builds a synthetic arm-tree of *-variance.md reports under a temp
# dir with hand-crafted Pass/Fail tables and asserts the aggregator computes
# the expected detection_rate / false_positive_rate — proving aggregation
# without ever invoking `claude`.
#
# Bash 3.2 compatible. No `set -e`.

# -------- Part A: decide() unit tests --------

. scripts/db-gate-race/score.sh --lib   # source decide() without running main

t() {
    # t detA0 fpA0 detB1 fpB1 detB2 fpB2 expected
    local got
    got="$(decide "$1" "$2" "$3" "$4" "$5" "$6")"
    if [ "$got" = "$7" ]; then
        echo "PASS $7 (got=$got)"
    else
        echo "FAIL want=$7 got=$got  (args: $1 $2 $3 $4 $5 $6)"
        exit 1
    fi
}

# B2 clears bar (+25pp det, +5pp fp): ship-B2
t 0.40 0.05 0.55 0.06 0.65 0.10   ship-B2
# nothing beats A0 by 20pp: park
t 0.60 0.05 0.68 0.06 0.72 0.08   park
# B1≈B2 both beat A0, |score diff|<10pp: ship-B1 (point-don't-own)
t 0.40 0.05 0.66 0.06 0.68 0.07   ship-B1
# only B2 clears (B1 misses the detection margin): ship-B2
t 0.40 0.05 0.55 0.05 0.65 0.06   ship-B2
# B2 fp just over ceiling (0.11) disqualifies an otherwise-clearing variant;
# B1 also fails to clear -> park
t 0.40 0.05 0.50 0.05 0.65 0.11   park

echo "all decide() tests passed"

# -------- Part B: aggregation parser tests --------

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_ROOT}"' EXIT

ARM_DIR="${TMPDIR_ROOT}/B2"
mkdir -p "${ARM_DIR}"

# defect-scenario report 1: two "text" assertions.
# assertion 0: Pass=4 Fail=1 -> detection contribution 4/5 = 0.8
# assertion 1: Pass=3 Fail=2 -> detection contribution 3/5 = 0.6
cat > "${ARM_DIR}/defect-missing-index-01-variance.md" <<'EOF'
# Behavioral Eval Variance Report — defect-missing-index-01

**Scenario:** `defect-missing-index-01`
**Iterations:** 5

## Per-assertion pass rates

| # | Description | Pass | Fail | Pass rate | Classification |
|---|---|---|---|---|---|
| 0 | Mentions missing index | 4 | 1 | 80% | flaky |
| 1 | Mentions query plan | 3 | 2 | 60% | flaky |

## Classification thresholds
EOF

# defect-scenario report 2: one "text" assertion.
# assertion 0: Pass=5 Fail=0 -> detection contribution 5/5 = 1.0
cat > "${ARM_DIR}/defect-n-plus-one-01-variance.md" <<'EOF'
# Behavioral Eval Variance Report — defect-n-plus-one-01

**Scenario:** `defect-n-plus-one-01`
**Iterations:** 5

## Per-assertion pass rates

| # | Description | Pass | Fail | Pass rate | Classification |
|---|---|---|---|---|---|
| 0 | Mentions N+1 pattern | 5 | 0 | 100% | stable |

## Classification thresholds
EOF

# clean-scenario report 1: one "absent" assertion.
# Pass = no false flag = 4, Fail = false flag raised = 1
# fp contribution = 1/5 = 0.2
cat > "${ARM_DIR}/clean-indexed-query-01-variance.md" <<'EOF'
# Behavioral Eval Variance Report — clean-indexed-query-01

**Scenario:** `clean-indexed-query-01`
**Iterations:** 5

## Per-assertion pass rates

| # | Description | Pass | Fail | Pass rate | Classification |
|---|---|---|---|---|---|
| 0 | Does not flag indexed query | 4 | 1 | 80% | flaky |

## Classification thresholds
EOF

# clean-scenario report 2: one "absent" assertion.
# Pass=5 Fail=0 -> fp contribution = 0/5 = 0.0
cat > "${ARM_DIR}/clean-paginated-query-01-variance.md" <<'EOF'
# Behavioral Eval Variance Report — clean-paginated-query-01

**Scenario:** `clean-paginated-query-01`
**Iterations:** 5

## Per-assertion pass rates

| # | Description | Pass | Fail | Pass rate | Classification |
|---|---|---|---|---|---|
| 0 | Does not flag paginated query | 5 | 0 | 100% | stable |

## Classification thresholds
EOF

# Expected: detection_rate = mean(0.8, 0.6, 1.0) = 0.8
# Expected: false_positive_rate = mean(0.2, 0.0) = 0.1
# n_defect_assertions = 3, n_clean_assertions = 2

result="$(aggregate_arm "${ARM_DIR}")"
# aggregate_arm prints: detection_rate<TAB>false_positive_rate<TAB>n_defect<TAB>n_clean
IFS="$(printf '\t')" read -r det fp ndef ncln <<EOF_RESULT
${result}
EOF_RESULT

check_float() {
    # check_float label got want
    local ok
    ok="$(awk -v a="$2" -v b="$3" 'BEGIN{d=a-b; if(d<0)d=-d; print (d<0.0001)?"1":"0"}')"
    if [ "$ok" = "1" ]; then
        echo "PASS $1 ($2 ~= $3)"
    else
        echo "FAIL $1 got=$2 want=$3"
        exit 1
    fi
}

check_float "detection_rate" "$det" "0.8"
check_float "false_positive_rate" "$fp" "0.1"

if [ "$ndef" = "3" ]; then
    echo "PASS n_defect_assertions (3)"
else
    echo "FAIL n_defect_assertions got=$ndef want=3"
    exit 1
fi

if [ "$ncln" = "2" ]; then
    echo "PASS n_clean_assertions (2)"
else
    echo "FAIL n_clean_assertions got=$ncln want=2"
    exit 1
fi

echo "all aggregation tests passed"
echo "all score tests passed"
