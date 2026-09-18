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
  whatever free-text string the upstream check produced. There is no
  separate structured "reason" field anywhere in the persisted schema for
  hold, review, or gate-breach outcomes.

## Also true of the frozen fixture, and would otherwise look like a discovery

- The fixture contains **no value-level `null` anywhere in the whole
  envelope** — a full recursive walk of the parsed JSON (all keys, all list
  elements) finds zero `null` values. Every "missing" or "not applicable"
  case in this fixture is represented by section-level absence (see
  `comparators`/`integrity_evidence` above) or by an empty string (the
  no-ticker `symbol` case), never by JSON `null`. An arm reporting "I found a
  null and handled it" is not describing this fixture.

## What a `screen-discovered` claim requires
1. A named screen behaviour that the frozen envelope cannot support.
2. Evidence of WHEN the need arose (the prompt or edit that surfaced it).
3. A testable acceptance criterion for the proposed contract change.

Absent any of the three, the entry is recorded as unsubstantiated and scores
nothing.
