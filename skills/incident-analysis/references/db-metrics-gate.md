# Database Metrics Gate — Queries and Decision Branch

Read at INVESTIGATE Step 3 when JDBC or connection errors are present, before the first database metric query; the mandatory rule stays in `SKILL.md`. Moved verbatim from `SKILL.md`.

  **Required queries (incident window + baseline, in parallel per Constraint 13):**

  | Metric | Tier 1 (`list_time_series`) | Tier 2 (REST API via `curl` + `gcloud auth print-access-token`) |
  |--------|----------------------------|----------------------------------------------------------------|
  | Connection count | `cloudsql.googleapis.com/database/network/connections` | Same metric via Monitoring REST API |
  | CPU utilization | `cloudsql.googleapis.com/database/cpu/utilization` | Same metric via Monitoring REST API |
  | Query rate | `cloudsql.googleapis.com/database/mysql/questions` (MySQL) or `cloudsql.googleapis.com/database/postgresql/transaction_count` (PostgreSQL) | Same metric via Monitoring REST API |

  **Decision branch:**

  | DB metrics vs baseline | Diagnosis | Investigation route |
  |------------------------|-----------|-------------------|
  | Connections, CPU, query rate all **normal** (within 1.5x baseline) | **App-side pool exhaustion** — connections held too long, not too many | Investigate application: slow queries holding connections, transaction scope changes, connection leak, pool sizing (max size, timeout, leak detection). Check deployment history for code changes affecting connection lifecycle. |
  | Connections **elevated** (approaching or at `max_connections`) | **Database-level exhaustion** — too many consumers | Investigate database: `max_connections` setting, per-service pool sizing, total connection demand across all consumers. Consider connection isolation (dedicated instances for critical services like auth). |
  | CPU **elevated** (>80%) or query rate **spiked** | **Database under load** — slow queries or query volume | Investigate database: slow query log, query plan regressions, lock contention. Check for new query patterns from recent deployments. |

  Rows are not mutually exclusive. When multiple conditions are present (e.g., connections elevated AND CPU spiked), combine diagnoses: the database is both oversubscribed and overloaded.

  **Anti-pattern this prevents:** Concluding "shared database starvation" from application-side JDBC errors when the database itself is healthy. In one investigation, this led to incorrect action items ("isolate auth service DB") that were revised after database metrics showed normal connection count, CPU, and query rate — the issue was app-side pool exhaustion (connections held too long under normal DB load).
