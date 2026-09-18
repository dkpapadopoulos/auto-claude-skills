# Advance disclosures — frozen before launch

Anything below is `supplied-in-advance`. A contract-delta entry restating one of
these earns ZERO credit as `screen-discovered`, regardless of how the arm
describes finding it.

This file is never shown to either arm. It is not a briefing — listing
something here does not tell the arms anything; it only prevents a later
rediscovery from being banked as insight.

## Stated in the brief
- The screen renders an execution list from a frozen report envelope.
- The envelope is the only data source; no network, no database.

## Discoverable by reading the repo (therefore NOT screen-discovered)

- `expected_fee_chf` may be null in principle; `enrich_order_dicts`
  (`src/dion/proposal/report.py:55-56`) comments that a missing fee "stays
  None (not 0.0) so the renderer can show a visible gap rather than a
  plausible-but-wrong 'free trade'". **But `run_review` cannot actually
  produce that state** — `compute_order_fees`
  (`src/dion/proposal/fees.py:36-90`) appends an `OrderFee` for every order
  unconditionally (`else: commission = 0.0` is its only fallback), and
  `per_order_fees_chf` (`src/dion/review/pipeline.py:1037-1039`) is built as
  `{of.instrument_id: of.total_one_way_chf for of in fee_result.per_order}`
  from that same result, over the identical order list that
  `enrich_order_dicts` receives (`report.py:171-178`, both sourced from
  `proposal.order_suggestions`). So `per_order_fees_chf.get(iid)` never
  misses, and `expected_fee_chf` is null in no reachable run. (Traced before
  either arm existed; the pilot's Finding A.)
- `comparators` and `integrity_evidence` are fields on the `ReviewReport`
  dataclass (`src/dion/proposal/report.py:70-90`) but are **absent entirely**
  from the persisted JSON — not null, not present-with-empty-value. `_store_report`
  (`src/dion/review/pipeline.py:2192-2202`) builds the stored payload from an
  explicit 8-key `json.dumps({...})` literal (`portfolio_state`,
  `eligibility_summary`, `optimizer_summary`, `proposal_summary`,
  `drift_analysis`, `metric_comparison`, `action_items`, `fx_exposure`) that
  names neither key. Verified directly against the frozen fixture
  (`tests/fixtures/design_seed_pilot/review_report_envelope.json`): its
  `data.report` object has exactly those 8 keys, and `"comparators"` /
  `"integrity_evidence"` are absent from it. A reader who writes
  `report["integrity_evidence"] is None` gets a `KeyError`, not `None`.
- `_get_instrument_symbols` (`src/dion/review/pipeline.py:1359-1386`) returns
  `""` for an instrument with no `ticker` alias row, and its docstring states
  the intended rendering: "Returns "" when no ticker alias exists so the
  renderer falls back to the internal id rather than a symbol-less row." The
  frozen fixture exercises both branches: of its 5 orders, 3 resolve a ticker
  (`FFLC`, `IWQU`, `SPMO` — instrument ids `inst-fflc`, `inst-iwqu`,
  `inst-spmo`) and 2 do not (`inst-aggs`, `inst-puls`, both `symbol: ""`).
  (Verified against the fixture directly; the pilot's Finding B.)
- The declared Numeric Policy in `CLAUDE.md` (`## Numeric Policy` section):
  quantities `DECIMAL(18,8)`, money amounts `DECIMAL(18,4)`, prices/FX rates
  `DECIMAL(18,8)`. **Correction to the original brief:** CLAUDE.md states only
  this table — it does **not** say "serializers emit floats" anywhere; that
  phrase does not appear in the file. The float-emission fact is separately
  discoverable by reading `report.py`'s `enrich_order_dicts`, which casts
  amounts with `float(...)` (`report.py:42-43`) before serializing, and by
  observing that the fixture's numeric fields are full-precision Python
  floats (e.g. `expected_fee_chf: 16.4233459875452`), not
  `DECIMAL(18,4)`-formatted strings. Both routes (code + fixture) are
  available without building anything, so the underlying fact stays
  supplied-in-advance — the brief's phrasing just over-attributed it to
  CLAUDE.md, and the "quantities" row of the table is not actually exercised
  anywhere in the execution-list path.
- Runs that fail a gate before proposal construction — the preflight
  reconciliation gate, or the strategic-exposure feasibility check — store
  **no report at all**. `run_review` (`src/dion/review/pipeline.py`) has
  eleven `return ReviewResult(...)` sites; every one except the final
  `status="completed"` return (line ~1239) passes `report=None` and returns
  before `_store_report` is ever reached (called once, at line 1162, on the
  success path only). **Correction to the original brief:** the code does not
  use the word "blocked" for these outcomes — the actual status strings are
  `preflight_error`, `preflight_breach`, `exposure_policy_infeasible`, and
  several data-quality statuses (`no_resolved_instruments`, `fx_gap_current`,
  `insufficient_history`, `insufficient_data`, `implausible_prices`,
  `no_rebalance_required`, `health_check_completed`). "Blocked runs" is an
  accurate paraphrase of the effect (no report persisted), not a term found
  in the code.
- Action items carry only a free-text `description` string, not a structured
  reason code. `build_review_report`'s action-items block
  (`src/dion/proposal/report.py:214-259`) emits `{"type", "instrument_id",
  "description"}` dicts; the `review_needed` case always uses the fixed
  literal `"Manual review required"` with no per-instance detail, and
  `fx_warning`/`fx_review_gate`/`eligibility_warning` descriptions are
  whatever free-text string the upstream check produced. **Correction (fix
  round 1): this is scoped to action items specifically, not to "the
  persisted schema" as originally stated** — `eligibility_summary` (one of
  the 8 persisted keys) does carry a structured reason, addressed below.
- `eligibility_summary.details[].reason` is a genuinely structured
  per-instrument reason, not a fixed literal. `EligibilityResult.reason`
  (`src/dion/eligibility/engine.py:15`) is populated by `check_eligibility`
  (`engine.py:17-73`), persisted verbatim via `[asdict(r) for r in
  eligibility_results]` into `eligibility_summary["details"]`
  (`report.py:147-152`). Under the `retail_safe` rule the two branches
  differ sharply: `eligible` emits the flat literal `reason="UCITS-flagged
  instrument"` (`engine.py:51`), while `restricted` emits a templated,
  per-instrument reason — `reason=f"Non-UCITS instrument ({domicile}),
  restricted under {rule}"` (`engine.py:58`), naming the actual domicile and
  rule. **The frozen fixture exercises only the `eligible` branch** —
  verified directly against the fixture: all 5 `eligibility_summary.details`
  entries have `status: "eligible"` and the identical flat string
  `"UCITS-flagged instrument"`. The richer restricted-branch template is
  therefore visible only by reading `engine.py`, not by reading the fixture,
  which makes it repo-discoverable and NOT screen-discovered under this
  file's own test. An arm claiming "the screen can't explain why an
  instrument is held back, and I'd add a structured reason" is restating a
  field the schema already provides (joinable by `instrument_id`) and earns
  no credit.
- `orders[].reason` (`OrderSuggestion.reason`, `src/dion/optimizer/contract.py:119`)
  is a separate free-text field, populated in `size_orders`
  (`src/dion/proposal/engine.py:150-160`) as `f"Increase from {current:.4f}
  to {proposed:.4f}"` / `f"Reduce from {current:.4f} to {proposed:.4f}"`.
  Present in the fixture on every order, e.g. `inst-aggs`:
  `"Increase from 0.1324 to 0.3780"` — verified directly. This is
  weight-change rationale for an order that WAS placed, not a hold/review/
  block reason, so it should not be confused with the eligibility case
  above — but it is a reason field the fixture already carries, so it is
  not bankable as a discovery either.

## Also true of the frozen fixture, and would otherwise look like a discovery

- The fixture contains **no value-level `null` anywhere in the whole
  envelope** — a full recursive walk of the parsed JSON (all keys, all list
  elements) finds zero `null` values. That half is verified and stands. The
  enumeration that followed it was wrong and is corrected here: "missing" and
  "not applicable" take **three** forms in this fixture, not two.
  1. **Section-level absence** — `comparators` / `integrity_evidence` above.
  2. **An empty string**, in **two** places rather than one: the no-ticker
     `symbol` case (`proposal_summary.orders[0]` and `[3]`) *and*
     `action_items[].instrument_id`, empty on **4 of the 9** action items —
     the `fx_warning`, `fx_review_gate` and `eligibility_warning` entries,
     which are portfolio-level and name no instrument.
  3. **An empty collection**, a form the original sentence excluded entirely —
     `drift_analysis.snapshot_drift` (`{}`),
     `optimizer_summary.policy_violations` (`[]`), and at envelope level
     `findings` (`[]`) and `statement_ids` (`[]`).

  An arm reporting "I found a null and handled it" is still not describing this
  fixture. An arm reporting any of the three forms above is describing
  something real — and something disclosed here, so it banks nothing.

- `drift_analysis.drift_max_pct` is a **percentage sitting beside
  fraction-valued siblings in the same object.** Measured against the frozen
  fixture: `drift_max_pct` is `24.567194849977945` while its neighbour
  `proposal_drift["inst-aggs"]` is `-0.24567194849977944` — the same quantity,
  exactly 100× apart, in adjacent keys of one object. It is computed that way
  at `src/dion/proposal/engine.py:189`
  (`max(abs(v) for v in proposal_drift.values()) * 100`). A screen that formats
  the object with one rule is wrong by two orders of magnitude on one key; a
  screen that gets it right did so by reading the code or by noticing the
  ratio. Either route is available before building anything, so this is
  supplied-in-advance and earns nothing as `screen-discovered`.

- `drift_analysis.snapshot_drift` is `{}` **only because `if previous_weights:`
  was false** (`src/dion/proposal/engine.py:183`) — there was no prior snapshot,
  so the loop that fills it never ran. The envelope carries nothing that
  distinguishes that from "compared, and nothing drifted". The screen therefore
  cannot tell "we have no baseline" from "you have not drifted", and those
  imply opposite things to a reader about to trade. This is the likeliest
  single entry on either arm's contract delta — rubric **R7** is anchored on
  exactly this state, so arm engagement is near-certain and it is bankable as a
  disclosure today. It was traced before either arm existed.

## What a `screen-discovered` claim requires
1. A named screen behaviour that the frozen envelope cannot support.
2. Evidence of WHEN the need arose (the prompt or edit that surfaced it).
3. A testable acceptance criterion for the proposed contract change.

Absent any of the three, the entry is recorded as unsubstantiated and scores
nothing.
