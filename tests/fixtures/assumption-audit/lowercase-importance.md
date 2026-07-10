# Discovery: latency fix

## Assumption Ledger

Logic chain: We achieve funnel recovery because the assumptions below hold.

| id | belief | category | importance | evidence_kind | source_ref | observed_at | grade | kill_threshold |
|----|--------|----------|------------|---------------|------------|-------------|-------|----------------|
| A1 | Users abandon at step 3 due to latency | customer | H | direct_metric | posthog:funnel_q2#step3 | 2026-07-01 | B | dropoff stays >30% -> kill |
| A2 | Competitors will not match pricing | competitor | M | expert_judgment | PM interview | 2026-07-08 | D | untested (cutoff) |
| A3 | Analogous fix worked for onboarding flow | capability | high | analogous | docs/CI.md#Required | 2026-07-05 | C |  |

## Options

| option | summary |
|--------|---------|
| do-nothing | keep current funnel |
| A | rebuild step 3 |
