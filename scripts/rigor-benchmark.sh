#!/bin/bash
# rigor-benchmark.sh — score a testing-rigor mechanism against the seeded corpus.
# Usage: rigor-benchmark.sh --mechanism adequacy --split dev|held-out
# Advisory tool; prints a metrics summary. Exit 0 always.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAC="${ROOT}/skills/project-verification/scripts/coverage-adequacy-check.sh"

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
    if [ "$flagged" -eq 1 ]; then _tp=$((_tp+1)); echo "PASS ${id}"; else _fn=$((_fn+1)); echo "MISS ${id} (${klass})"; fi
  else
    if [ "$flagged" -eq 1 ]; then _fp=$((_fp+1)); echo "FP ${id} (${klass})"; else _tn=$((_tn+1)); echo "PASS ${id}"; fi
  fi
done < "$_manifest"

_rec="NA"; _den=$(( _tp + _fn )); [ "$_den" -gt 0 ] && _rec=$(( _tp * 100 / _den ))
_prec="NA"; _pden=$(( _tp + _fp )); [ "$_pden" -gt 0 ] && _prec=$(( _tp * 100 / _pden ))
_cprec="NA"; _cden=$(( _tn + _fp )); [ "$_cden" -gt 0 ] && _cprec=$(( _tn * 100 / _cden ))
echo "---"
echo "mechanism=${_mech} split=${_split} recall=${_rec} precision=${_prec} control_precision=${_cprec} tp=${_tp} fn=${_fn} fp=${_fp} tn=${_tn}"
exit 0
