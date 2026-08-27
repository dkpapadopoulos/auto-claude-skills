## Why

`CLAUDE.md` has always required: *"Any false-block rate over the log MUST filter `select(.would_block == true)`."* `scripts/shadow-adjudicate.sh` contained **zero references to that field**. `_episodes()` selected `[.repo,.branch,.session_token,.ts,.record_id]` with no filter and `cmd_next` offered every record, so the instrument that decides the IMPLEMENT-leg deny-flip was measuring the wrong population.

Measured on the live corpus: **17 records — 2 `would_block:true`, 15 attested non-blocks.** The attested records were added deliberately by #169 (schema 3) so the corpus could observe how often *attestation* rather than real work satisfied the leg. They cannot contain a false block by construction.

Before / after on that corpus:

| | before | after |
|---|---|---|
| `episodes` | 11 | 13 |
| would-block (rate population) | — | **2** |
| attestation-only | — | 11 |
| `unadjudicated` | **11** | **2** |

The reported backlog was almost entirely the population that cannot produce the measurement. Diluting the denominator biases the rate toward **clearing** the deny-flip — the unsafe direction, and the same bias `CLAUDE.md` already warns about for `cannot_check` vs `missing`.

## What Changes

- **`_episode_wb`** classifies each episode `yes` / `no` / `malformed` from the raw `would_block` boolean.
- **`cmd_status`** counts adjudicated, agent-claimed, the three verdicts **and the repo-diversity set** over would-block episodes only, and reports the attestation-only population on its own line so #169's observation stays visible.
- **`cmd_next`** never offers a non-would-block record: adjudicating one is meaningless work whose verdict cannot inform a false-block rate.

Three decisions are deliberate and each is pinned by test:

- **The filter is NOT inside `_episodes()`.** That function is shared; filtering there would erase the attested population from `--status` entirely — exactly what #169 added it to make visible.
- **Membership reads `would_block` only, never `impl_evidence_kind`.** The two correlate perfectly in today's data, which is the trap: that field is format-frozen and describes *evidence*, not rate membership. Coupling them would recreate the implicit contract that broke this reader.
- **The diversity floor moved too.** If attestation episodes could satisfy the ≥2-repo requirement, the corpus would clear diversity with zero false-block evidence spanning repos.

**The mixed-episode rule is DEFINED, not discovered.** An episode is a would-block episode if **any** of its records would have blocked. "Any" is chosen because it is anchor-independent: `_episodes()` anchors `episode_id` on the first record by timestamp, so a rule consulting only the anchor would classify the same episode differently by arrival order. Both orders are asserted. No mixed episode exists today — an undefined rule is how this instrument came to be wrong in the first place.

A missing or non-boolean `would_block` is reported as **excluded**, never coerced to `false`: folding an unknown into the bucket that looks safe is the same bias in miniature.

## Capabilities

### Modified Capabilities

- `pdlc-safety`: the pre-registered false-block rate, its denominator and its diversity floor must be computed over the population the pre-registration names, and any other population the instrument reports must be labelled as an observation rather than pooled into the measurement.

## Impact

- `scripts/shadow-adjudicate.sh` — one classifier, three call-site changes. Diagnostic-only; still never sourced by the guard, still absent from `_GATE_ENFORCE_LIBS`, still emits no `permissionDecision` and writes no gate state.
- `tests/test-shadow-adjudicate.sh` — 8 new assertions, red before the change.
- **No `predicate_version` or `schema_version` bump.** This is a READER fix: the records are unchanged and the firing predicate is unchanged (#169 explicitly kept it at 2). The old reader violated an already-published rule rather than measuring a different predicate, so a bump would misrepresent the defect and orphan a valid corpus.

## Consequence for #173

The corrected population makes the pre-registered checkpoint's own decision rule fire earlier and harder: **2 would-block episodes**, not 11, against a floor of 29. The ≥2-repo requirement is already satisfied at n=2 (one episode in each of two repos), so the episode count is the sole remaining barrier. At the observed accrual this is years away, not weeks — which is materially stronger evidence for revisiting the `<10%` threshold than "11 of 29" ever was.
