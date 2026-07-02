# 4xx / Empty-Resource Blind Spot

A `severity>=ERROR` or `status>=500` filter structurally excludes **4xx**. A **404 for a
resource that does not exist yet** (e.g. a feature flag enabled before its backing record is
provisioned) is a client-error the app does not log at ERROR severity: it surfaces at the
**gateway / access-log layer** (reverse proxy, ingress, API gateway) or in an app-level status
field (e.g. `jsonPayload.response_status`), not the app's exception stream.

**Do not equate a clean 5xx/ERROR sweep with "backend healthy."** When the sweep is clean but the
user still fails reproducibly, treat "no 5xx" as a positive clue: drop the severity floor, widen
to **4xx**, and query the gateway access logs + the app-level status field **before** concluding
"client-side." The trap is naming the blind spot ("can't see 4xx / access logs not captured") and
stopping, rather than pivoting to the layer that holds it.

Applies at Step 2c (Quantify User-Facing Impact) and any point where a "backend clean" conclusion
is about to be drawn from an ERROR/5xx-only query.
