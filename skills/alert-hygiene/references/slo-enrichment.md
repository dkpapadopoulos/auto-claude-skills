# alert-hygiene — Stage 1 SLO config enrichment script

Read at SKILL.md Stage 1 before SLO config enrichment. Its rules (preconditions, the two artifacts always written, name normalization, the report line) stay in SKILL.md. Moved verbatim from SKILL.md.

**Flow:**

```bash
REPO="${github_org}/monitoring"

# Short-circuit if preconditions not met
if [ -z "${github_org:-}" ]; then
  echo '{"status":"unavailable","reason":"github_org_not_provided","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
elif ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
  echo '{"status":"unavailable","reason":"gh_not_available","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
else
  # Step 1: fetch (checked)
  if ! gh api "repos/$REPO/contents/tf/slo-config.yaml" \
       --jq '.content' > "$WORK_DIR/slo-raw-b64.txt" 2>"$WORK_DIR/slo-fetch-err.txt"; then
    echo '{"status":"unavailable","reason":"fetch_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 2: decode (checked)
  elif ! base64 -d < "$WORK_DIR/slo-raw-b64.txt" > "$WORK_DIR/slo-config.yaml" 2>/dev/null; then
    echo '{"status":"unavailable","reason":"decode_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 3: extract service names (checked — Ruby stdlib YAML, no PyYAML)
  elif ! ruby -ryaml -rjson -e '
    cfg = YAML.safe_load(File.read(ARGV[0])) || {}
    services = (cfg["services"] || []).map { |s| s["name"] }.compact
      .map { |n| n.downcase.gsub(/[_.]/, "-").gsub(/-(prod|staging|pta)$/, "") }
    File.write(ARGV[1], JSON.generate(services))
    File.write(ARGV[2], JSON.generate({
      status: services.empty? ? "empty" : "ok",
      count: services.length
    }))
  ' "$WORK_DIR/slo-config.yaml" "$WORK_DIR/slo-services.json" \
    "$WORK_DIR/slo-source-status.json" 2>"$WORK_DIR/slo-parse-err.txt"; then
    echo '{"status":"unavailable","reason":"parse_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  fi
  rm -f "$WORK_DIR/slo-raw-b64.txt"
fi
```
