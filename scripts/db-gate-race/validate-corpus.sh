#!/bin/bash
# Validate db-gate-race corpus structure. Exit 0 = valid, 1 = invalid.
# Bash 3.2 compatible; no set -e.
PACK="${1:-tests/fixtures/db-gate-race/evals/corpus.json}"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }
[ -f "$PACK" ] || { echo "missing pack: $PACK"; exit 1; }
jq -e '.' "$PACK" >/dev/null 2>&1 || { echo "pack is not valid JSON: $PACK"; exit 1; }
fail=0
defects=$(jq '[.[]|select(.id|startswith("defect-"))]|length' "$PACK")
cleans=$(jq  '[.[]|select(.id|startswith("clean-"))]|length' "$PACK")
[ "$defects" -ge 18 ] || { echo "need >=18 defect scenarios, got $defects"; fail=1; }
[ "$cleans"  -ge 8  ] || { echo "need >=8 clean scenarios, got $cleans"; fail=1; }
# every defect has >=1 text assertion; every clean has only absent assertions
bad_defect=$(jq '[.[]|select(.id|startswith("defect-"))|select([.assertions[].kind//"text"]|index("text")|not)]|length' "$PACK")
bad_clean=$(jq  '[.[]|select(.id|startswith("clean-"))|select([.assertions[].kind]|any(.!="absent"))]|length' "$PACK")
[ "$bad_defect" -eq 0 ] || { echo "$bad_defect defect scenarios lack a text assertion"; fail=1; }
[ "$bad_clean"  -eq 0 ] || { echo "$bad_clean clean scenarios have non-absent assertions"; fail=1; }
# taxon coverage: each taxon appears in >=3 defect ids
for t in unsafe-migration missing-index n-plus-one offset-pagination lock-risk; do
  n=$(jq --arg t "$t" '[.[]|select(.id|startswith("defect-"+$t))]|length' "$PACK")
  [ "$n" -ge 3 ] || { echo "taxon $t underrepresented ($n<3)"; fail=1; }
done
# every scenario has the required behavioral-pack fields
missing_fields=$(jq '[.[]|select((has("id") and has("prompt") and has("expected_behavior") and has("assertions"))|not)]|length' "$PACK")
[ "$missing_fields" -eq 0 ] || { echo "$missing_fields scenarios missing required fields (id/prompt/expected_behavior/assertions)"; fail=1; }
[ "$fail" -eq 0 ] && echo "corpus valid: $defects defect + $cleans clean" || echo "corpus INVALID"
exit $fail
