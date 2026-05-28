#!/usr/bin/env bash
# race-truncation-defaults.sh — A/B harness for Task 0 of context-economy-defaults.
#
# Runs the same prompt twice via `claude -p --output-format json`:
#   Baseline: env vars unset (Anthropic defaults: MCP=25000, Bash unbounded)
#   Capped:   BASH_MAX_OUTPUT_LENGTH=20000 MAX_MCP_OUTPUT_TOKENS=10000
#
# Each run's JSON output stays clean (no in-band sentinel keys). Duration is
# recorded in a sidecar file `<run>.duration` so parsing the JSON later does
# not break. Per-run JSON validity is verified; if either run produces invalid
# JSON or fails outright, the harness exits non-zero and the summary file
# starts with an `# INVALID:` banner so the gate verdict cannot be filled in
# by mistake.
#
# NOT a regression test — explicit invocation only; not auto-run by tests/run-tests.sh.
# Bash 3.2 compatible (macOS /bin/bash). jq required for parsing.

set -u

print_help() {
    cat <<'EOF'
Usage: race-truncation-defaults.sh --prompt "<text>" [--out <dir>]
       race-truncation-defaults.sh --prompt-file <path> [--out <dir>]

Required:
  --prompt "<text>"        Prompt to run twice. For Task 0, use a real
                           incident-analysis investigation against an authenticated
                           GCP project that produces noisy MCP log output.
  --prompt-file <path>     Read prompt from file.

Optional:
  --out <dir>              Directory for run artifacts (default: ./race-results/)
  --help                   Show this help.

Outputs (in --out):
  baseline.json            Raw `claude -p --output-format json` output, env defaults
  baseline.duration        Seconds the baseline run took (sidecar)
  capped.json              Raw output with BASH_MAX_OUTPUT_LENGTH=20000,
                           MAX_MCP_OUTPUT_TOKENS=10000
  capped.duration          Seconds the capped run took (sidecar)
  comparison.md            Side-by-side summary for human judgment.
                           Prefixed with `# INVALID:` banner if any run failed.

Exit codes:
  0   both runs completed AND produced valid JSON
  1   either run failed or produced invalid JSON; summary will be banner-prefixed
  2   bad invocation

Manual-judgment criteria (NOT automated):
  - PASS: capped run reaches a comparable conclusion to baseline AND token/cost
    delta is material (>=10% reduction).
  - ABORT: capped run misses the investigation conclusion (e.g., truncated logs
    hid the smoking-gun line) OR delta <10% (cap not worth the fidelity loss).

The Anthropic-documented default for MAX_MCP_OUTPUT_TOKENS is 25000 with a
warning threshold at 10000. We are setting EXACTLY 10000 (the floor) — not
the Confluence-suggested 8000 — to respect Anthropic's warning.
EOF
}

PROMPT=""
PROMPT_FILE=""
OUT_DIR="./race-results"

while [ $# -gt 0 ]; do
    case "$1" in
        --prompt)        PROMPT="${2:-}"; shift 2 ;;
        --prompt-file)   PROMPT_FILE="${2:-}"; shift 2 ;;
        --out)           OUT_DIR="${2:-}"; shift 2 ;;
        --help|-h)       print_help; exit 0 ;;
        *)               echo "Unknown arg: $1" >&2; print_help >&2; exit 2 ;;
    esac
done

if [ -n "$PROMPT_FILE" ] && [ -z "$PROMPT" ]; then
    if [ ! -f "$PROMPT_FILE" ]; then
        echo "ERROR: prompt file not found: $PROMPT_FILE" >&2
        exit 2
    fi
    PROMPT="$(cat "$PROMPT_FILE")"
fi

if [ -z "$PROMPT" ]; then
    echo "ERROR: --prompt or --prompt-file is required" >&2
    print_help >&2
    exit 2
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: claude CLI not found on PATH" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required" >&2
    exit 2
fi

mkdir -p "$OUT_DIR"
BASELINE_FILE="${OUT_DIR}/baseline.json"
BASELINE_DUR="${OUT_DIR}/baseline.duration"
CAPPED_FILE="${OUT_DIR}/capped.json"
CAPPED_DUR="${OUT_DIR}/capped.duration"
SUMMARY_FILE="${OUT_DIR}/comparison.md"

BASELINE_OK=0
CAPPED_OK=0

# run_claude <label> <outfile> <durfile>
# Writes JSON to outfile (stdout only on success; stderr discarded so an error
# message does not corrupt JSON). Records seconds elapsed to durfile.
# Returns 0 if the command exited 0 AND the JSON is valid.
run_claude() {
    local label="$1"
    local outfile="$2"
    local durfile="$3"
    local start_ts
    local end_ts
    start_ts="$(date +%s)"
    echo "=== Running ${label} ==="
    if ! claude -p --output-format json "$PROMPT" >"$outfile" 2>/dev/null; then
        end_ts="$(date +%s)"
        printf '%d\n' "$((end_ts - start_ts))" > "$durfile"
        echo "  FAILED: ${label} exited non-zero" >&2
        return 1
    fi
    end_ts="$(date +%s)"
    printf '%d\n' "$((end_ts - start_ts))" > "$durfile"
    if ! jq empty "$outfile" 2>/dev/null; then
        echo "  FAILED: ${label} produced invalid JSON" >&2
        return 1
    fi
    echo "  done in $((end_ts - start_ts))s — valid JSON captured"
    return 0
}

extract_field() {
    # $1 = json file, $2 = jq path (e.g. .total_cost_usd)
    local file="$1"
    local path="$2"
    if [ ! -f "$file" ]; then
        printf "n/a"
        return
    fi
    if ! jq empty "$file" 2>/dev/null; then
        printf "n/a"
        return
    fi
    jq -r "$path // \"n/a\"" "$file" 2>/dev/null | head -1
}

# --- Run 1: baseline ---
unset BASH_MAX_OUTPUT_LENGTH
unset MAX_MCP_OUTPUT_TOKENS
if run_claude "baseline (env defaults)" "$BASELINE_FILE" "$BASELINE_DUR"; then
    BASELINE_OK=1
fi

# --- Run 2: capped ---
export BASH_MAX_OUTPUT_LENGTH=20000
export MAX_MCP_OUTPUT_TOKENS=10000
if run_claude "capped (BASH=20000, MCP=10000)" "$CAPPED_FILE" "$CAPPED_DUR"; then
    CAPPED_OK=1
fi

# --- Summarize ---
echo ""
echo "=== Extracting metrics ==="

B_COST="$(extract_field "$BASELINE_FILE" '.total_cost_usd')"
C_COST="$(extract_field "$CAPPED_FILE" '.total_cost_usd')"
B_DUR="$(cat "$BASELINE_DUR" 2>/dev/null || echo n/a)"
C_DUR="$(cat "$CAPPED_DUR" 2>/dev/null || echo n/a)"
B_IN="$(extract_field "$BASELINE_FILE" '.usage.input_tokens')"
C_IN="$(extract_field "$CAPPED_FILE" '.usage.input_tokens')"
B_OUT="$(extract_field "$BASELINE_FILE" '.usage.output_tokens')"
C_OUT="$(extract_field "$CAPPED_FILE" '.usage.output_tokens')"
B_CACHE_R="$(extract_field "$BASELINE_FILE" '.usage.cache_read_input_tokens')"
C_CACHE_R="$(extract_field "$CAPPED_FILE" '.usage.cache_read_input_tokens')"

{
    if [ "${BASELINE_OK}" -ne 1 ] || [ "${CAPPED_OK}" -ne 1 ]; then
        echo "# INVALID: one or both runs failed or produced unparseable JSON."
        echo ""
        echo "Do NOT fill in a PASS/ABORT verdict from this report — re-run the"
        echo "harness until both runs complete with valid JSON."
        echo ""
        echo "  baseline: $([ "${BASELINE_OK}" -eq 1 ] && echo OK || echo FAILED)"
        echo "  capped:   $([ "${CAPPED_OK}" -eq 1 ] && echo OK || echo FAILED)"
        echo ""
        echo "---"
        echo ""
    fi
    echo "# Race-test results: truncation defaults"
    echo ""
    echo "Run date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "## Metrics"
    echo ""
    echo "| Metric | Baseline (defaults) | Capped (20k/10k) |"
    echo "|---|---|---|"
    echo "| total_cost_usd | ${B_COST} | ${C_COST} |"
    echo "| input_tokens | ${B_IN} | ${C_IN} |"
    echo "| output_tokens | ${B_OUT} | ${C_OUT} |"
    echo "| cache_read_input_tokens | ${B_CACHE_R} | ${C_CACHE_R} |"
    echo "| duration_seconds | ${B_DUR} | ${C_DUR} |"
    echo ""
    echo "## Manual judgment (fill in)"
    echo ""
    echo "- [ ] Capped run reached the same investigation conclusion as baseline."
    echo "- [ ] Token/cost delta is >= 10% (material)."
    echo "- [ ] No critical log lines were truncated below visibility."
    echo ""
    echo "**Verdict:** PASS / ABORT"
    echo ""
    echo "**Notes:**"
    echo ""
} > "$SUMMARY_FILE"

cat "$SUMMARY_FILE"
echo ""
echo "Artifacts:"
echo "  ${BASELINE_FILE}  (baseline JSON; ${BASELINE_DUR} duration sidecar)"
echo "  ${CAPPED_FILE}    (capped JSON;   ${CAPPED_DUR} duration sidecar)"
echo "  ${SUMMARY_FILE}"

if [ "${BASELINE_OK}" -ne 1 ] || [ "${CAPPED_OK}" -ne 1 ]; then
    echo ""
    echo "Exit status: 1 (one or both runs invalid; see summary file banner)"
    exit 1
fi

echo ""
echo "Next: paste the PASS/ABORT verdict into"
echo "  docs/plans/2026-05-28-race-truncation-results.md"
echo "and notify the implementer."
