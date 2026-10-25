# runtime-validation — Lighthouse perf overlay script

Read at SKILL.md Step 3 before running the Lighthouse perf overlay (a Lighthouse CLI was detected in Step 1). The overlay's rules (report-only, lab not field, what the report MUST state) stay in SKILL.md. Moved verbatim from SKILL.md.

```bash
# Self-contained port probe — re-probe candidate ports to set PERF_URL.
# (The Step 1 port probe echoes findings but does not export a variable;
#  this block is self-contained so the overlay always has a URL to target.)
PERF_URL=""
for _port in 3000 5173 8000 8080; do
  _code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:${_port}/" 2>/dev/null)
  if [ "${_code}" != "000" ] && [ -n "${_code}" ]; then
    PERF_URL="http://localhost:${_port}/"
    break
  fi
done

# Self-gate: global lighthouse OR a local install in node_modules/.bin (checked directly,
# no npx — so it never triggers a network download and is portable across npm versions).
# A package.json-listed-but-uninstalled lighthouse correctly skips here.
if [ -n "${PERF_URL}" ] && { command -v lighthouse >/dev/null 2>&1 || node_modules/.bin/lighthouse --version >/dev/null 2>&1; }; then
  mkdir -p tests/artifacts/validation/
  npx lighthouse "${PERF_URL}" --quiet --chrome-flags="--headless" \
    --only-categories=performance --output=json --output-path=stdout 2>/dev/null \
    | jq '{perf_score: (.categories.performance.score * 100 | floor),
           lcp_ms: .audits["largest-contentful-paint"].numericValue,
           cls:    .audits["cumulative-layout-shift"].numericValue,
           tbt_ms: .audits["total-blocking-time"].numericValue}' \
    | tee tests/artifacts/validation/lighthouse.json
fi
```
