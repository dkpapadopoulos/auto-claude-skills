---
type: gotcha
title: A "no resource yet" 404 is invisible to severity>=ERROR / status>=500 sweeps
description: Persistent per-user failures with a clean 5xx sweep are often 4xx (esp. 404); query the gateway access-log layer and app-level response_status, not the app exception stream.
tags: [incident-analysis, logging, gcp, investigation, 4xx]
source: skills/incident-analysis/SKILL.md:Step 2c
timestamp: 2026-07-02T00:00:00Z
---

When a client-visible failure is **persistent and per-user** but a `severity>=ERROR` /
`httpRequest.status>=500` sweep comes back clean, the failure is often a **4xx** — most
commonly a **404 for a resource that does not exist yet** (e.g. a feature flag enabled before
its backing record is provisioned).

A 404 is a client-error (4xx) response that the app does not log at ERROR severity, so it is
excluded by both `severity>=ERROR` and `status>=500`. It also surfaces at the **gateway /
access-log layer** (reverse proxy, ingress, API gateway) or in an **app-level status field**
(e.g. `jsonPayload.response_status`), NOT in the app container's exception stream.

A clean 5xx/ERROR sweep therefore does not establish that the backend is healthy. When the sweep
is clean but the user still fails reproducibly, "no 5xx" is itself a clue — the 4xx layer is the
one worth querying: the gateway access logs and the app-level status field, before the failure is
attributed to the client. A common trap is naming the blind spot ("can't see 4xx / access logs
not captured") and stopping there rather than pivoting to the layer that holds it.

**Real case (healthcare SaaS, 2026-07):** a mobile "overview" screen failed to load for users
whose feature flag was enabled but whose backing record had never been provisioned. The owning
service returned **404**; an ERROR/5xx sweep scoped to that service's container showed nothing on
the reproduced day, and the 404 was visible only at the API-gateway layer via its `response_status`
field. A first-pass "backend clean → client-side" conclusion had to be revised once the 4xx layer
was queried.
