# Access Gate — Auth-Fix Prompt and Tool Access Summary

Read at MITIGATE Step 1 when the Tier 1 probe fails with an auth error, and at Step 1b before presenting the tool access summary; the gate's rules stay in `SKILL.md`. Moved verbatim from `SKILL.md`.

## Step 1: the auth-fix prompt

   > "MCP Observability auth expired (`<error>`). Tier 1 provides metrics, traces, and error reporting that gcloud CLI cannot. Fix now with:
   > ```
   > ! gcloud auth application-default login
   > ```
   > This opens a browser for re-authentication. Proceed?"

## Step 1b: the tool access summary

```
Tool access:
  MCP observability: available | auth expired (fixable) | unavailable
  gcloud auth:       active (project X) | expired | not configured
  kubectl context:   available (context Y) | unavailable
  GitHub CLI (gh):   authenticated | not authenticated | not installed

Investigation domains:
  Logs:              ✓ complete (Tier N) | ⚠ partial | ✗ unavailable
  Metrics:           ✓ complete (Tier N) | ⚠ partial (Tier 2 — no list_time_series) | ✗ unavailable
  K8s state:         ✓ complete | ✗ unavailable
  Source analysis:    ✓ complete | skipped | ✗ unavailable
  Trace correlation: ✓ complete (Tier 1 only) | skipped | ✗ unavailable
```
