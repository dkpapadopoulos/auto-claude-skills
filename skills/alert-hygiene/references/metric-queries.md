# alert-hygiene — Stage 3b metric query detail

Read at SKILL.md Stage 3b before the first metric query. The Mandatory Query Parameters table, the Result Quality Gate and Steps 2, 4 and 5 stay in SKILL.md. Moved verbatim from SKILL.md.

## Step 1 — PromQL to Cloud Monitoring mapping

Most PromQL conditions use metrics that ARE queryable via Cloud Monitoring under a mapped name:

| PromQL pattern | Cloud Monitoring equivalent | Example |
|---|---|---|
| `kubernetes_io:METRIC_PATH` | `kubernetes.io/METRIC_PATH` | `kubernetes_io:container_restart_count` → `kubernetes.io/container/restart_count` |
| `SERVICE_COM:METRIC` | `SERVICE.com/METRIC` | `dbinsights_googleapis_com:perquery_latencies` → `dbinsights.googleapis.com/perquery/latencies` |
| `METRIC_NAME` (custom) | `prometheus.googleapis.com/METRIC_NAME/SUFFIX` | `jvm_threads_live_threads` → `prometheus.googleapis.com/jvm_threads_live_threads/gauge` |
| `METRIC_NAME_count` (histogram _count) | `prometheus.googleapis.com/METRIC_NAME/histogram` | `http_server_duration_milliseconds_count` → `prometheus.googleapis.com/http_server_duration_milliseconds/histogram` (use `distributionValue.count` for request counts) |

For custom Prometheus metrics, the suffix depends on the metric type: try `/gauge` first, then `/counter`, `/summary`, `/histogram` if no data returns. **Important:** When PromQL references `METRIC_count` (the `_count` component of a histogram), the Cloud Monitoring equivalent is the parent histogram type (`/histogram`), NOT a separate `_count` metric. The request count is in the `distributionValue.count` field of the distribution result. If none return data, list metric descriptors with `filter=metric.type = starts_with("prometheus.googleapis.com/METRIC_PREFIX")` to find the actual suffix.

## Step 3 — Tier 2 query pattern

**Tier 2 query pattern** (uses session temp file per Behavioral Constraint 2):

```bash
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/ah-XXXXXX)}"
FILTER_FILE=$(mktemp "$WORK_DIR/ts-filter-XXXXXX.txt")
cat > "$FILTER_FILE" << 'FILTER'
metric.type = "prometheus.googleapis.com/jvm_threads_live_threads/gauge"
AND metric.labels.container = "recommendation-service"
AND resource.labels.cluster = "example-cluster-prod"
FILTER

TOKEN=$(gcloud auth print-access-token)
FILTER_ENC=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(open(sys.argv[1]).read().strip().replace('\n', ' ')))" "$FILTER_FILE")

# Note: REDUCE_MAX for gauges; use REDUCE_SUM for counters per the table above
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries?filter=$FILTER_ENC&interval.startTime=${START_TIME}&interval.endTime=${END_TIME}&aggregation.alignmentPeriod=3600s&aggregation.perSeriesAligner=ALIGN_MAX&aggregation.crossSeriesReducer=REDUCE_MAX&pageSize=100000" \
  -o "$WORK_DIR/ts-result.json" ; rm -f "$FILTER_FILE"
```

## Multi-query patterns

| Metric kind | Approach | Example |
|---|---|---|
| **CUMULATIVE DISTRIBUTION** (e.g., perquery latencies) | `ALIGN_DELTA` extracts the delta distribution per period. Read `distributionValue.mean` for average latency and `distributionValue.count` for query volume. | `dbinsights.googleapis.com/perquery/latencies` + ALIGN_DELTA daily → mean latency per day |
| **Error rate ratios** (5xx / total) | Two queries: (1) filter by status label for errors, (2) unfiltered for total. Divide in Python. Write both results to `$WORK_DIR`. | Query with `metric.labels.status=starts_with("5")` for errors, without for total. Compute `error_count / total_count`. |
| **High-cardinality counters** (e.g., 1,000+ containers) | Use `aggregation.crossSeriesReducer=REDUCE_SUM` to aggregate across all series. Gives total restart rate without enumerating each container. | `kubernetes.io/container/restart_count` + ALIGN_DELTA 1h + REDUCE_SUM → total restarts/hour across all containers |
| **Histogram-based error rates** (e.g., `rate(metric_count{status=~"5.."}[5m])`) | When PromQL uses `_count` from a histogram metric (e.g., `http_server_duration_milliseconds_count`), the Cloud Monitoring equivalent is the `/histogram` type — NOT a separate `_count` metric. Query `prometheus.googleapis.com/METRIC_NAME/histogram` with `ALIGN_DELTA`. The `distributionValue.count` field gives the request count per period. For error-rate ratios: query with status label filter for 5xx (count = error volume), then without filter (count = total volume). Compute ratio from the two `count` sums. | `prometheus.googleapis.com/http_server_duration_milliseconds/histogram` + ALIGN_DELTA 1h → `distributionValue.count` per period. Two queries: with `http_status_code=~"5.."` for errors, without for total. |
| **Custom PromQL with no Cloud Monitoring equivalent** | Rare — most Prometheus metrics map via `prometheus.googleapis.com/METRIC/SUFFIX`. Try `/gauge`, `/counter`, `/summary`, `/histogram` suffixes. If none return data, list metric descriptors with `starts_with` filter. | `metricDescriptors?filter=metric.type = starts_with("prometheus.googleapis.com/METRIC_PREFIX")` |

**Tier 2 two-query ratio pattern** (error rate example):

```bash
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/ah-XXXXXX)}"

# Query 1: error count (5xx)
FILTER_ERR=$(mktemp "$WORK_DIR/ts-err-XXXXXX.txt")
cat > "$FILTER_ERR" << 'FILTER'
metric.type = "prometheus.googleapis.com/http_server_requests_seconds_count/summary"
AND metric.labels.status = starts_with("5")
AND metric.labels.application = "SERVICE_NAME"
FILTER
# ... curl with crossSeriesReducer=REDUCE_SUM&pageSize=100000 to $WORK_DIR/ts-err-result.json

# Query 2: total count
FILTER_TOTAL=$(mktemp "$WORK_DIR/ts-total-XXXXXX.txt")
cat > "$FILTER_TOTAL" << 'FILTER'
metric.type = "prometheus.googleapis.com/http_server_requests_seconds_count/summary"
AND metric.labels.application = "SERVICE_NAME"
FILTER
# ... curl with crossSeriesReducer=REDUCE_SUM&pageSize=100000 to $WORK_DIR/ts-total-result.json

# Compute ratio
python3 -c "
import json
err = sum(float(pt['value']['doubleValue']) for s in json.load(open('$WORK_DIR/ts-err-result.json')).get('timeSeries',[]) for pt in s['points'] if 'doubleValue' in pt.get('value',{}))
total = sum(float(pt['value']['doubleValue']) for s in json.load(open('$WORK_DIR/ts-total-result.json')).get('timeSeries',[]) for pt in s['points'] if 'doubleValue' in pt.get('value',{}))
print(f'error_rate={err/total*100:.2f}% ({err:.0f}/{total:.0f})') if total > 0 else print('no data')
"
rm -f "$FILTER_ERR" "$FILTER_TOTAL"
```
