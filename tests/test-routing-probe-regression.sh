#!/bin/bash
# Non-regression gate over the intent-routing probe.
#
# This asserts that no consultation-routing case gets WORSE than the frozen baseline
# in tests/probes/intent-routing/baseline.json. It is deliberately NOT an acceptance
# gate: the baseline records five violated cases that are known open defects, and
# fixing them is the point of the work in flight. Improvements pass and are reported.
#
# Deterministic and free — it runs the real activation hook against an isolated HOME
# and makes no model call. The paid native conformance runner is NOT wired here; see
# tests/probes/README.md.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="${ROOT}/tests/probes/intent-routing/intent_probe.py"
BASELINE="${ROOT}/tests/probes/intent-routing/baseline.json"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not available — routing probe regression NOT checked"
  exit 0
fi
if [ ! -f "$PROBE" ] || [ ! -f "$BASELINE" ]; then
  echo "FAIL: probe or baseline missing (${PROBE}, ${BASELINE})"
  exit 1
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
rmdir "$OUT" 2>/dev/null

if ! python3 "$PROBE" --out "$OUT" >/dev/null 2>&1 < /dev/null; then
  echo "FAIL: intent probe did not complete"
  exit 1
fi

python3 - "$BASELINE" "$OUT/summary.json" <<'PY'
import json, sys
baseline = json.load(open(sys.argv[1]))["cases"]
current = {f"{r['arm']}/{r['case']}": r for r in json.load(open(sys.argv[2]))["matrix"]}

regressions, improvements, missing = [], [], []
for name, was in baseline.items():
    now = current.get(name)
    if now is None:
        missing.append(name)
        continue
    # A case regresses when it stops being satisfied, or when a satisfied case
    # becomes vacuous (satisfied by selecting nothing, which pins nothing).
    if was["satisfied"] and not now["satisfied"]:
        regressions.append(f"{name}: satisfied -> violated {now['violations']}")
    elif was["satisfied"] and not was["vacuous"] and now["vacuous"]:
        regressions.append(f"{name}: informative -> vacuous")
    elif not was["satisfied"] and now["satisfied"]:
        improvements.append(f"{name}: violated -> satisfied")

for name in missing:
    print(f"FAIL: baseline case absent from this run: {name}")
for line in regressions:
    print(f"FAIL: {line}")
for line in improvements:
    print(f"  improved (allowed, and the goal): {line}")

if missing or regressions:
    print(f"\nFAILED: {len(regressions)} regression(s), {len(missing)} missing case(s)")
    sys.exit(1)
print(f"\nPASSED: {len(baseline)} cases, no regression"
      + (f", {len(improvements)} improved" if improvements else ""))
PY
