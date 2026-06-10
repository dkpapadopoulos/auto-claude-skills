---
type: postmortem
status: unresolved
date: 2026-04-08
severity: high
services: [hcs-gb, backend-core, calendar]
---

# Postmortem: HCS-GB Billing Tab 500 — Calendar REST API Removed in Core v4.132.0

**Date:** 2026-04-08
**Cluster:** oviva-prod1 (oviva-k8s-prod, europe-west3)
**Severity:** High (100% billing tab failure for GB coaches, forced logout)

## 1. Summary

GB coaches are immediately logged out of the platform when attempting to access the billing tab.

`backend-core` v4.132.0, deployed on 2026-04-07 at 20:14 UTC, removed the legacy Calendar REST API (`CalendarEventRESTService.java`) as part of the calendar microservice extraction (CORE-6079, CORE-6097, CORE-6085). The `hcs-gb` service was not migrated — it still calls the removed endpoint via `com.oviva.core.openapi.client.api.CalendarApi.getEvents()`, which now returns HTTP 404. This causes all `/rest/billing-tracker/patient/{id}/session-buckets.json` requests to fail with 500 ("Request to core failed"). The OCS frontend interprets the billing 500 as a session failure and terminates the coach's session, forcing a logout. The incident began when the first coach accessed the billing tab the next morning (07:16 UTC) and remains **unresolved** — rollback to v4.131.0 is unsafe because the accompanying DB migration (`V535.6085__drop_unused_calendar_tables.sql`) has already dropped the legacy calendar tables.

## 2. Impact

**User-facing:**
- 100% of billing-tracker session-buckets requests return HTTP 500
- Every coach who navigates to the billing tab is immediately logged out
- Billing workflows (session tracking, billable unit review) are fully blocked for GB market
- 150+ distinct billing errors across dozens of patient IDs since 07:16 UTC
- Zero successful session-buckets requests since the incident began

**Infrastructure:**
- `hcs-gb` (1 pod: `hcs-gb-66d6fc6984-2qgwr`, namespace `prod`): all CalendarApi.getEvents calls return 404
- `backend-core` (v4.132.0): Calendar REST endpoint no longer exists; returns 404 with no body
- Calendar microservice: healthy (returning 200 on `/app/v2/calendar/events.json`), but has independent `TaskExecutionStateChangedEvent` processing failures
- `backend-core` also returning 500 on `/api/rest/mobile-api/v5/measurements/measurements.json/_bulk` with calendar-related errors

**Duration:** 2026-04-08 07:16 UTC → **ongoing** (not yet resolved as of 10:30 UTC, ~3.5+ hours)

## 3. Action Items

| Priority | Action | Current state | Owner | Due | Status |
|----------|--------|---------------|-------|-----|--------|
| P0 | Restore billing-tab functionality: either (A) add compatibility endpoint in Core v4.132.1 wrapping `CalendarClientImpl.fetchCalendarEvents()`, or (B) update hcs-gb to call Calendar microservice directly at `http://calendar:8080/app/v2/calendar/events.json` | Endpoint removed in v4.132.0; `CalendarClientImpl` exists in Core but has no REST exposure for hcs-gb | Backend-core team / HCS-GB team | 2026-04-08 (today) | Open |
| P1 | Add cross-service integration tests for hcs-gb → Core API contract — the CalendarApi.getEvents endpoint was removed without verifying that all consumers had migrated | No consumer-side contract test exists for this endpoint | Backend-core team + HCS-GB team | 2026-04-15 | Open |
| P1 | Fix OCS frontend to not terminate the entire coach session on a billing-tab 500 — a billing failure should show an error message, not force logout | OCS frontend treats billing 500 as session expiry (same pattern as [2026-03-09 postmortem](2026-03-09-hb-prod-coaches-logged-out-backend-core-timeouts.md)) | OCS frontend team | 2026-04-22 | Open |
| P2 | Add API deprecation process — REST endpoints consumed by other services should go through a deprecation cycle (mark deprecated → verify consumer migration → remove) before deletion | No formal deprecation process; endpoint was removed in one release | Platform/Architecture team | 2026-04-30 | Open |
| P2 | Investigate Calendar `TaskExecutionStateChangedEvent` processing failures (Camel route `task-execution-state-changed-event-consumer` throwing `TechnicalException`) — may be an independent issue or secondary effect of the calendar decommissioning | Calendar service logging repeated message delivery failures | Calendar team | 2026-04-15 | Open |
| P3 | Evaluate making Flyway migration `V535.6085` (table drops) a separate release from the code removal — dropping tables in the same release as removing the API prevents safe rollback | Migration and code removal shipped together in v4.132.0 | Backend-core team | 2026-04-30 | Open |

## 4. Root Cause & Trigger

**Root cause:** `backend-core` v4.132.0 removed `CalendarEventRESTService.java` (the JAX-RS REST endpoint for calendar events) as part of a multi-ticket calendar microservice extraction. The removal was spread across commits CORE-6079 (delete calendar service classes), CORE-6097 (migrate internal callers to `CalendarClientImpl`), and CORE-6085 (drop database tables). Internal Core callers were migrated to the new `CalendarClientImpl` which calls the Calendar microservice directly at `http://calendar:8080/app/v2/calendar/events.json`. However, `hcs-gb` — an external consumer — was not migrated. It still uses `com.oviva.core.openapi.client.api.CalendarApi`, an OpenAPI-generated client that targets the now-removed Core endpoint.

**Causal chain:**
```
Core v4.132.0 deployed (Apr 7 20:14 UTC)
  → CalendarEventRESTService.java removed (CORE-6079 PR 3-E)
  → V535.6085 drops legacy calendar DB tables
  → hcs-gb CalendarApi.getEvents() → HTTP 404 (no body)
  → PatientSessionServiceImpl wraps as TechnicalException: "Request to core failed"
  → billing-tracker /session-buckets.json → HTTP 500
  → OCS frontend interprets 500 as session failure → coach logged out
```

**Trigger:** First coach accessing the billing tab after the overnight deployment (07:16 UTC, ~09:16 CEST).

## 5. Timeline (all timestamps UTC)

| Timestamp | Precision | Event | Evidence source |
|-----------|-----------|-------|-----------------|
| 2026-04-07 13:31 | minute | Calendar service deployed (Flux patch) | k8s_cluster audit logs |
| 2026-04-07 20:14 | minute | `backend-core` v4.132.0 deployed to prod via Flux | k8s_cluster audit logs: `deployments.patch namespaces/prod/deployments/backend-core` |
| 2026-04-07 20:14 | minute | Flyway migration V535.6085 drops legacy calendar tables on Core startup | Migration file in v4.132.0; no Flyway log found but migration is idempotent `DROP TABLE IF EXISTS` |
| 2026-04-08 07:16:21 | exact | First `CalendarApi.getEvents` 404 error in hcs-gb | hcs-gb ERROR logs: "getEvents call failed with: 404 - [no body]" |
| 2026-04-08 07:16 – 10:30+ | exact | Continuous 500 errors on all billing-tracker session-buckets requests | hcs-gb ERROR logs: 150+ entries, zero successful requests |
| 2026-04-08 ~09:00 | approximate | Coaches report being logged out when accessing billing tab | User report (incident trigger) |
| 2026-04-08 10:30 | minute | Investigation identifies root cause: removed CalendarEventRESTService.java in Core v4.132.0 | Source analysis: GitHub compare v4.131.0...v4.132.0 |
| — | — | **Recovery: NOT YET ACHIEVED** | — |

## 6. Contributing Factors

1. **No consumer-side contract testing (most impactful):** The Core Calendar REST API was consumed by hcs-gb via an OpenAPI-generated client, but no integration test verified that all consumers had been migrated before the endpoint was removed. The CORE-6079/CORE-6097 tickets only migrated internal Core callers.

2. **DB migration coupled with code removal:** The Flyway migration (`V535.6085__drop_unused_calendar_tables.sql`) that drops legacy calendar tables shipped in the same release as the code removal. This prevents safe rollback — v4.131.0's DAO would query non-existent tables. Separating table drops into a later release would have preserved the rollback path.

3. **12-hour deployment-to-detection gap:** The Core deployment happened at 20:14 UTC (evening), and the first error appeared at 07:16 UTC (next morning business hours). No automated test or synthetic monitor exercises the billing-tracker → Core CalendarApi path, so the break was only detected by real user traffic.

4. **Disproportionate frontend error handling (recurring):** The OCS frontend terminates the coach's session on billing-tab 500 errors instead of showing an error message. This is the same pattern identified in the [2026-03-09 postmortem](2026-03-09-hb-prod-coaches-logged-out-backend-core-timeouts.md) — a backend failure in one feature area causes complete session loss. This amplifies the user-facing severity of any billing-related backend error.

## 7. Lessons Learned

**What went well:**
- Investigation quickly narrowed from symptom (coach logout) to root cause (CalendarApi 404) using structured log analysis
- The `CalendarClientImpl` replacement already exists in Core and the Calendar microservice is healthy — fix paths are clear
- Error logs contained full stack traces with the exact exception chain, making root cause identification fast

**What went wrong:**
- Calendar REST API was removed without verifying all consumers had migrated — hcs-gb was missed
- No API deprecation process exists — the endpoint went from "in use" to "deleted" in one release
- No synthetic monitoring or smoke test covers the billing-tracker → Core CalendarApi call path
- Rollback is blocked by the coupled DB migration

**Where we got lucky:**
- Only the GB market's billing tab is affected (not CH, not other features)
- The Calendar microservice itself is healthy — the fix only requires re-exposing the endpoint or updating hcs-gb's client, not rebuilding calendar functionality
- Core's `CalendarClientImpl` already has the `fetchCalendarEvents` method that wraps the Calendar microservice call — a compatibility shim is straightforward

## 8. Investigation Notes

**Confirmed root cause (high confidence):**
- Zero CalendarApi 404 errors before Core v4.132.0 deployment (verified: Apr 7 00:00–20:14 UTC)
- First error at 07:16 UTC Apr 8, corresponding to first coach billing-tab access
- GitHub compare v4.131.0...v4.132.0 shows `CalendarEventRESTService.java` (417 lines) **removed**
- 286 files changed in v4.132.0, with massive calendar code removal across `calendar/`, `calendarscheduler/`, `calendarmigration/` packages

**Ruled-out hypotheses:**
- Calendar microservice failure: Calendar service returns 200 on `/app/v2/calendar/events.json` (evidence: backend-core INFO logs show "Response code: 200" for all Calendar calls)
- hcs-gb deployment: No hcs-gb deployment patches in the last 3 days (evidence: k8s_cluster audit logs)
- Network/routing issue: The 404 with empty body is consistent with a removed JAX-RS endpoint, not a network failure (which would produce connection errors or timeouts)
- Database issue: Core's own queries work fine (Hibernate warnings only, no errors); Calendar microservice is healthy

**Open questions:**
1. Are other external consumers of the removed Calendar REST API affected beyond hcs-gb?
2. Is the Calendar `TaskExecutionStateChangedEvent` failure related to the calendar decommissioning or an independent issue?
3. What is the exact URL path that hcs-gb's CalendarApi client calls on Core? (OpenAPI spec not examined)

**Evidence coverage:**
- Logs: complete (Tier 2 gcloud CLI)
- K8s state: unavailable (kubectl unreachable — cluster API timeout, likely requires VPN)
- Metrics: partial (MCP auth expired — `invalid_rapt`)
- Source analysis: complete (GitHub API — `oviva-ag/ocs_backend`)
- Trace correlation: unavailable (MCP auth expired)

**Gaps:**
- Pod replica count and distribution not verified from live cluster (kubectl unavailable)
- User-facing error rate not quantified from load balancer metrics (MCP auth expired)
- hcs-gb pod health/restart count not verified
- Flyway migration execution not confirmed from logs (migration log not found, inferred from table-dependent behavior)

### Investigation Path

**Decision tree:**
```
├─ Billing-tracker 500: "Request to core failed" (hcs-gb ERROR logs)
│  └─ Why does CalendarApi.getEvents return 404?
│     ├─ ✗ Calendar microservice down (Core→Calendar calls return 200)
│     ├─ ✗ Network/routing issue (404 with no body = removed endpoint, not network error)
│     ├─ ✗ hcs-gb misconfigured (no hcs-gb deployment in 3 days)
│     └─ ✓ Core endpoint removed in v4.132.0
│        └─ Why was hcs-gb not migrated?
│           └─ ✓ CORE-6079/CORE-6097 only migrated internal Core callers
│              Evidence: GitHub compare shows CalendarEventRESTService.java removed
│              Zero 404 errors before v4.132.0 deploy, first error after
│              └─ Disconfirming checks: 2/2 pass → ROOT CAUSE CONFIRMED
├─ Recovery: NOT YET ACHIEVED
├─ Blast radius: hcs-gb billing tab only (GB market); CH not affected
└─ Recurring pattern: OCS frontend logout-on-500 (same as 2026-03-09 postmortem)
```

**Evidence steps:**

1. **Error fingerprint** — What is failing?
   Evidence: hcs-gb ERROR logs → `CalendarApi.getEvents call failed with: 404 - [no body]` wrapping to `TechnicalException: Request to core failed` on all `session-buckets.json` requests.
   Conclusion: 100% failure rate on billing-tracker endpoint due to downstream CalendarApi 404.

2. **Onset timing** — When did it start?
   Evidence: Log query for `getEvents call failed with: 404` across Apr 1–8 → zero errors before Apr 7 20:14 UTC (Core deploy), first error at Apr 8 07:16:21 UTC.
   Conclusion: Error onset correlates perfectly with Core v4.132.0 deployment + next-morning business hours.

3. **Ruled-out: Calendar microservice** — Is the Calendar service down?
   Ruled out: Calendar is healthy (backend-core INFO logs: "Request to Calendar service ... Response code: 200" throughout incident window).

4. **Ruled-out: hcs-gb change** — Did hcs-gb change?
   Ruled out: No hcs-gb deployment patches in k8s_cluster audit logs for past 3 days.

5. **Source analysis** — What changed in Core v4.132.0?
   Evidence: GitHub compare v4.131.0...v4.132.0 → 286 files changed. `CalendarEventRESTService.java` (417 lines) **removed**. `CalendarEventServiceImpl.java` (1004 lines) removed. DB migration `V535.6085` drops legacy calendar tables.
   Conclusion: The endpoint hcs-gb calls was deliberately removed as part of calendar decommissioning.

6. **Rollback assessment** — Can we roll back Core?
   Evidence: Migration `V535.6085__drop_unused_calendar_tables.sql` drops `CORE_CALENDAR_EVENT_TE` and related tables. v4.131.0's `CalendarEventDaoImpl` queries these tables.
   Conclusion: Rollback unsafe — would cause `Table doesn't exist` errors.

**Reviewer takeaway:** A multi-ticket calendar decommissioning in Core removed a REST API consumed by hcs-gb without verifying all external consumers had migrated. The top action item is restoring billing functionality via a compatibility endpoint or hcs-gb client update.
