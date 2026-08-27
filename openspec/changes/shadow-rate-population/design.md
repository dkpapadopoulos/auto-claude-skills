# Design — the shadow corpus rate population (#213 follow-up, #173 input)

## The defect

`CLAUDE.md` published the rule — *filter `select(.would_block == true)`* — and the reader never implemented it. Not a drifted implementation: **zero references to the field.** `_episodes()` grouped every record; `cmd_next` offered every record.

That matters more than an ordinary counting bug because of *which* direction it errs. The 15 attested records cannot contain a false block, so pooling them can only ever shrink the observed rate. Every dilution of this denominator argues for **flipping the leg to deny**. The instrument was biased toward the enforcement-increasing conclusion, which is the one that needs the most evidence.

## Why the filter is not in `_episodes()`

The obvious fix is one `select` inside the shared grouper. It is wrong for a reason the file's own comment culture would predict: `_episodes()` is shared, and filtering there erases the attested population from the report entirely — which is precisely what #169 added those records to make visible. The change would have silently traded one measurement error for the loss of a different measurement.

So the population question is answered at the point of use: a classifier, plus filtering in the two callers that own a population decision.

## Why not `impl_evidence_kind`

In the current corpus `impl_evidence_kind == "attested"` and `would_block == false` coincide perfectly, which makes the former a tempting proxy. It is the trap. That field is **format-frozen** (`"none"`/`"attested"` are asserted in two test files and pinned in three specs) and describes what evidence was found, not whether the leg would have blocked. Binding rate membership to it would create exactly the kind of implicit cross-field contract that broke this reader in the first place. Membership reads the boolean, and only the boolean.

## The mixed-episode rule, defined in advance

An episode collapses records sharing `(repo, branch, session_token)` inside the window, so it can in principle hold both a would-block and an attested record. No such episode exists today — verified against the live keys, which are disjoint.

The rule is **"any record would have blocked"**, and the reason is not aesthetic. `_episodes()` anchors `episode_id` on the *first record by timestamp*. Any rule that consulted the anchor record would classify the same episode differently depending on which record happened to arrive first — a latent ordering bug in a statistical instrument, which is the worst place for one. "Any" is anchor-independent by construction. Both orders are pinned by test.

"Worst-verdict-wins" was considered as the analogue, since the file already uses it. It is the wrong analogue: that rule collapses *verdicts* over a single population, whereas this decides *membership*. Folding an attestation observation into a would-block episode's classification would misrepresent what was observed.

## Malformed values

A missing or non-boolean `would_block` is reported as excluded, never coerced to `false`. Coercion would file unknowns into the population that looks safe — the same bias as the original defect, one level down. The check is type-aware (`(.would_block|type) == "boolean"`) so a JSON *string* `"true"` cannot enter the rate population.

## No version bump

`predicate_version` changes when the firing predicate changes; it has not (#169 explicitly kept it at 2). `schema_version` describes fields present in records; the records are untouched. The old reader violated an already-published rule rather than measuring a legitimately different predicate, so bumping either would misrepresent the defect and orphan a corpus that is still valid.

The counter-case, recorded rather than dismissed: episode classification is itself part of the statistical predicate, so if machine-readable *analysis outputs* are ever persisted, those could carry their own `analysis_version`. That is additive tooling metadata, not a producer-side bump, and nothing persists such outputs today.

## Bash notes

No new TSV column was added to the `_episodes()` handoff. This file has three documented tab-collapse incidents — tab is IFS *whitespace*, so an empty field shifts every later column — and `cmd_status` already re-splits on `\x1f` for that reason. The classifier takes the existing comma-separated record-id list instead, so the fragile boundary is not widened.

## What this does not do

It does not adjudicate anything, and it does not move the corpus closer to the n=29 floor — it reveals that the corpus was further away than reported. It also does not change the guard: this script remains diagnostic-only, unsourced by any hook, absent from `_GATE_ENFORCE_LIBS`, emitting no `permissionDecision`.
