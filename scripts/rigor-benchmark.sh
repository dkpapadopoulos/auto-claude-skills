#!/bin/bash
# rigor-benchmark.sh — score a testing-rigor mechanism against the seeded corpus.
# Usage: rigor-benchmark.sh --mechanism adequacy --split dev|held-out
# Advisory tool; prints a metrics summary. Exit 0 always.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAC="${ROOT}/skills/project-verification/scripts/coverage-adequacy-check.sh"
BASELINE="${ROOT}/skills/project-verification/scripts/gate-gaming-check.sh"

command -v jq >/dev/null 2>&1 || { echo "recall=NA control_precision=NA (jq missing)"; exit 0; }

_mech="adequacy"; _split="dev"
while [ $# -gt 0 ]; do
  case "$1" in
    --mechanism) _mech="$2"; shift 2;;
    --split) _split="$2"; shift 2;;
    *) shift;;
  esac
done

_dir="${ROOT}/tests/fixtures/rigor-benchmark/${_split}"
_manifest="${_dir}/manifest.jsonl"
[ -f "$_manifest" ] || { echo "recall=NA control_precision=NA (no manifest)"; exit 0; }

_tp=0; _fn=0; _fp=0; _tn=0
_base_tp=0; _should_flag_n=0
_t0="$(date +%s)"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id="$(printf '%s' "$line" | jq -r '.id')"
  klass="$(printf '%s' "$line" | jq -r '.class')"
  should="$(printf '%s' "$line" | jq -r '.should_flag')"
  depr="$(printf '%s' "$line" | jq -r '.deprecated // empty')"
  [ -n "$depr" ] && continue
  diff_f="${_dir}/$(printf '%s' "$line" | jq -r '.diff')"
  cov_f="${_dir}/$(printf '%s' "$line" | jq -r '.coverage')"

  verdict="unverified"
  if [ "$_mech" = "adequacy" ] && [ -f "$diff_f" ]; then
    verdict="$(COVERAGE_ADEQUACY_LCOV="$cov_f" bash "$CAC" < "$diff_f" 2>/dev/null | head -1)"
  fi
  flagged=0; [ "$verdict" = "suspect" ] && flagged=1

  if [ "$should" = "true" ]; then
    _should_flag_n=$((_should_flag_n+1))
    if [ "$flagged" -eq 1 ]; then _tp=$((_tp+1)); echo "PASS ${id}"; else _fn=$((_fn+1)); echo "MISS ${id} (${klass})"; fi
    # Cheapest-baseline comparison: the existing gate-gaming regex detector, run over
    # the same should-flag case, so incremental_recall reflects what adequacy catches
    # on top of what the cheapest existing detector already caught.
    if [ -f "$diff_f" ] && [ -f "$BASELINE" ]; then
      _bverdict="$(bash "$BASELINE" < "$diff_f" 2>/dev/null | head -1)"
      [ "$_bverdict" = "suspect" ] && _base_tp=$((_base_tp+1))
    fi
  else
    if [ "$flagged" -eq 1 ]; then _fp=$((_fp+1)); echo "FP ${id} (${klass})"; else _tn=$((_tn+1)); echo "PASS ${id}"; fi
  fi
done < "$_manifest"
_t1="$(date +%s)"
_cost_seconds=$(( _t1 - _t0 ))

_rec="NA"; _den=$(( _tp + _fn )); [ "$_den" -gt 0 ] && _rec=$(( _tp * 100 / _den ))
_prec="NA"; _pden=$(( _tp + _fp )); [ "$_pden" -gt 0 ] && _prec=$(( _tp * 100 / _pden ))
_cprec="NA"; _cden=$(( _tn + _fp )); [ "$_cden" -gt 0 ] && _cprec=$(( _tn * 100 / _cden ))
# incremental_recall: cases adequacy catches that the cheapest baseline (gate-gaming
# regex detector) misses, as a percentage of all should-flag cases. Guards div-by-zero.
_inc="NA"
if [ "$_should_flag_n" -gt 0 ]; then
  _inc=$(( ( (_tp * 100 / _should_flag_n)) - ((_base_tp * 100 / _should_flag_n)) ))
fi
echo "---"
echo "mechanism=${_mech} split=${_split} recall=${_rec} precision=${_prec} control_precision=${_cprec} incremental_recall=${_inc} cost_seconds=${_cost_seconds} tokens=0 tp=${_tp} fn=${_fn} fp=${_fp} tn=${_tn} baseline_tp=${_base_tp}"
exit 0
