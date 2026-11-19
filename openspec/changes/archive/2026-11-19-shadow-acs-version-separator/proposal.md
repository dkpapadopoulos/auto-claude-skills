# Shadow readers apply the acs_version separator (#450)

## Why

#432 changed which pushes reach the REVIEW and IMPLEMENT shadow legs at plugin 3.103.1. #449 decided not to bump a predicate version for it and named `acs_version` 3.103.1 as the boundary: records written by an older plugin must not be pooled with later ones. That rule was prose. Neither reader read the field, so `--status`, `--rate-episodes`, `--next` and `--evidence-miss` pooled across the boundary and said nothing, the state #219 and #383 were fixed for on the predicate version.

## What changes

- `hooks/lib/shadow-corpus.sh` holds the rule once: the separator version, the predicate version of each leg it applies to, and a jq classifier (`acs_class`) that compares versions per component as numbers.
- `scripts/review-shadow-adjudicate.sh` and `scripts/shadow-adjudicate.sh` leave a record out of every population when its predicate is the one the separator names for that leg and its `acs_version` is below 3.103.1 or is not a `<n>.<n>.<n>` string. They report those records as pre-separator, with a count per cause, and refuse a label for one. Each refuses to run when the lib does not supply the rule.
- Two leftovers from #449: the guard no longer writes the `push-implement` phase-gate log line under the capture replay, and `scripts/shadow-adjudicate.sh --help` is answered before the producer-lib refusal.

## Decision recorded

#450 left two options open, report-only or exclude. Exclusion was taken: the rule #449 recorded already says such records must not be pooled, and a count beside a pooled rate leaves the rate wrong. Cost on the owner's corpora on 2026-11-19: 149 of 208 REVIEW predicate-3 records and 14 of 41 IMPLEMENT predicate-6 records excluded. Neither corpus held a label.

## Not changed

- No predicate or schema version, and no writer.
- Records of other predicate versions, which are reported as before.
- At any other predicate version the separator excludes nothing, so a record whose stamp failed validation is kept there.
