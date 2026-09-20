# Contract delta — execution-list screen

What `artifacts/execution-list.html` needed from
`tests/fixtures/design_seed_pilot/review_report_envelope.json` (envelope
`rev-b7bd753c33f9`, report `rpt-a3ade10d6cf9`) and could not get.

Nothing below was worked around on the way to the screen. Every gap renders as a
missing value (`—`, `--value-missing`, reason in the `title`) or as an explicit
"absent" line, never as a zero, a blank, or a number the UI invented.

Each entry states: **(1)** the screen behaviour that could not be built, **(2)** the
payload shape that would build it, **(3)** an acceptance criterion that fails today and
passes after the change, **(4)** whether it was known before starting or discovered
while building — and, if discovered, what surfaced it.

---

## 1. `orders[].symbol` is an empty string for two of five orders

**1 — Behaviour blocked.** The instrument column cannot name the instrument. `inst-aggs`
and `inst-puls` render `—` where `FFLC`, `IWQU` and `SPMO` render a ticker. A reader
cannot type those two rows into a broker ticket, so 48 208 CHF of the 97 746 CHF list —
both of the buys — is not placeable as shown. The screen marks those rows `No symbol`
rather than falling back to the `instrument_id`, because `inst-aggs` is not a ticker and
showing it in the ticker column would invite someone to try it.

**2 — Payload wanted.** A symbol that is either resolved or explicitly, typedly absent —
and, since a ticker is not unique across venues, the identifier a ticket actually needs:

```json
{
  "instrument_id": "inst-aggs",
  "symbol": "AGGS",
  "symbol_source": "instrument_master",
  "isin": "IE00BZ0G8977",
  "con_id": 412345678,
  "exchange": "ARCA"
}
```

and, when it genuinely cannot be resolved, `"symbol": null` with
`"symbol_source": "unresolved"` — never `""`. Empty string is indistinguishable from an
instrument that has no ticker, and the screen has to guess which it is.

**3 — Acceptance criterion.** For every order in a stored report envelope,
`symbol` is either a non-empty string or JSON `null`, never `""`; when it is `null`,
`symbol_source == "unresolved"` and at least one of `isin` / `con_id` is non-null.
A test asserts `all(o["symbol"] != "" for o in orders)` against a freshly stored
envelope, and fails on today's fixture.

**4 — Known before starting.** `tests/design_seed_pilot/test_fixture_adequacy.py` names
`symbol` as a "documented empty-string fallback for a subset of orders", and the two
empty values are visible on a first read of the fixture.

---

## 2. No price as-of timestamp for the limit bands

**1 — Behaviour blocked.** The screen cannot tell the reader how old the limit bands
are. `limit_low` / `limit_high` arrive with no quote time, no market-data date, and no
snapshot id. The envelope's only time is `summary.created_at`
(`2026-09-18 14:37:04`) — the moment the *report row* was written, which is not the
moment the *prices* were taken. A limit band whose age is unknown is a band you cannot
act on: it may be 30 seconds or 3 weeks stale, and the screen has no way to warn. There
is no "stale price" state on this screen for exactly that reason.

**2 — Payload wanted.**

```json
{
  "proposal_summary": {
    "priced_as_of": "2026-09-17T20:00:00Z",
    "price_source": "openbb.daily_close",
    "orders": [
      {
        "instrument_id": "inst-aggs",
        "reference_price": 59.29805,
        "reference_price_as_of": "2026-09-17T20:00:00Z",
        "limit_low": 59.1498,
        "limit_high": 59.4463,
        "limit_basis": "reference_price ±0.25%"
      }
    ]
  }
}
```

**3 — Acceptance criterion.** Every order carrying a `limit_low`/`limit_high` also
carries a `reference_price_as_of` parseable as a timezone-aware timestamp, and
`proposal_summary.priced_as_of` is present. A test asserts that no order has a limit
band without an as-of, and the screen renders a `Stale price` warning when the as-of is
older than the configured tolerance.

**4 — Discovered while building.** Surfaced when writing the table caption: every other
column could be given a unit and a meaning in one clause, and the limit columns could
not be given an age. It hardened when the reference price turned out to be recoverable
by arithmetic (`estimated_value_local / shares` equals the band midpoint to 5 decimals
on all five rows) — the screen deliberately does not do that division, because a price
the UI re-derives is a second source of truth, and it still would not have a timestamp.

---

## 3. No FX rate joining the local and analysis currencies

**1 — Behaviour blocked.** The screen shows order value in USD and fee and cash delta in
CHF, and cannot show the rate that connects them or let a reader check the conversion.
The FX panel's "FX rate used" row is `—`. This matters here more than usual: the same
envelope reports 98.8% USD exposure and two FX review-gate breaches, so the rate is the
number under the largest flagged risk on the page.

**2 — Payload wanted.** The rate as used, per order and once at the top, with its own
as-of — not as something to divide out:

```json
{
  "proposal_summary": {
    "fx_rates": {"USD/CHF": {"rate": 0.88, "as_of": "2026-09-17T20:00:00Z", "source": "flex_statement"}},
    "orders": [
      {"instrument_id": "inst-aggs", "fx_rate_to_analysis": 0.88, "currency": "USD", "analysis_currency": "CHF"}
    ]
  }
}
```

**3 — Acceptance criterion.** For every order whose `currency != analysis_currency`,
`fx_rate_to_analysis` is present and non-null, and
`abs(estimated_value_local * fx_rate_to_analysis - estimated_value_analysis) < 0.01`.
A test asserts both for each order in a stored envelope.

**4 — Discovered while building.** Surfaced when the totals row needed one currency and
the table had two. `estimated_value_analysis / estimated_value_local` is exactly 0.88 on
all five orders, so the rate is knowable — but a rate inferred by the screen is not the
rate the backend used, it is a rate that happened to reproduce it, and it carries no
as-of and no source.

---

## 4. No share quantities — current, or post-trade

**1 — Behaviour blocked.** The screen cannot show "hold 200 → 763", only "13.24% →
37.80%". A reader checking a fill against the position has to do the translation
themselves, which is the part the screen exists to remove. There is also no way to show
that a sell is not an over-sell: `portfolio_state` carries weights and one total value,
no per-instrument quantity.

**2 — Payload wanted.**

```json
{
  "proposal_summary": {
    "orders": [
      {"instrument_id": "inst-aggs", "current_shares": 302, "shares": 563, "post_trade_shares": 865}
    ]
  },
  "portfolio_state": {
    "holdings": {"inst-aggs": {"shares": 302, "market_value_local": 17908.0, "currency": "USD"}}
  }
}
```

**3 — Acceptance criterion.** For every order, `current_shares` and `post_trade_shares`
are present, and `post_trade_shares == current_shares + shares` for a buy and
`current_shares - shares` for a sell; `post_trade_shares >= 0` for every sell. A test
asserts the identity per order and fails today on `KeyError`.

**4 — Discovered while building.** Surfaced writing the post-trade column: the header
says "Post-trade" but the only post-trade fact in the envelope is a weight, and a weight
is not what gets entered into a ticket.

---

## 5. No net cash effect, and no cash balance to apply it to

**1 — Behaviour blocked.** The totals row leaves the cash column `—`. The individual
`cash_delta_chf` values are there, but the envelope supplies no aggregate, and the
screen does not sum the column: a UI-side total is a second, independently rounded
number the backend never produced, and the two disagree eventually. There is also no
cash balance anywhere in the envelope, so even a correct net (+1 329.85 CHF on these
five orders) could not be turned into "cash after: X" — which is the question a reader
actually has before releasing a list of orders.

**2 — Payload wanted.**

```json
{
  "proposal_summary": {
    "net_cash_delta_analysis": 1329.8526338767988,
    "cash_delta_includes_fees": false,
    "cash_before_analysis": 4210.55,
    "cash_after_analysis": 5486.58
  }
}
```

**3 — Acceptance criterion.** `net_cash_delta_analysis` is present and equals the sum of
`orders[].cash_delta_chf` to within 0.01; when `cash_before_analysis` is present,
`cash_after_analysis == cash_before_analysis + net_cash_delta_analysis - estimated_fees`
if `cash_delta_includes_fees` is false. A test asserts the reconciliation.

**4 — Discovered while building.** Surfaced at the totals row. The styleguide's "never
re-derive a number the backend already computed" turned a routine `sum()` into a gap:
once you refuse to derive it, the field is simply not there.

---

## 6. Whether `cash_delta_chf` includes the fee is undeclared

**1 — Behaviour blocked.** The screen cannot state the true cash movement per order.
`abs(cash_delta_chf) == estimated_value_analysis` exactly on all five orders, so the fee
is *evidently* excluded — but no field says so, and "evidently" is a convention that can
change under the screen without a signal. The page shows the fee in its own column and
says in the caption that cash deltas exclude it; that sentence is an inference, and it
is the only inference on the page.

**2 — Payload wanted.** `"cash_delta_includes_fees": false` on `proposal_summary` (see
§5), plus per-order `"cash_delta_gross_analysis"` / `"cash_delta_net_analysis"` if both
are meaningful.

**3 — Acceptance criterion.** `proposal_summary.cash_delta_includes_fees` is present and
boolean, and matches the data: if false, `abs(cash_delta_chf) == estimated_value_analysis`
for every order to within 0.01; if true,
`abs(cash_delta_chf) == estimated_value_analysis + expected_fee_chf`. A test asserts the
flag agrees with the arithmetic, so a silent convention change goes red.

**4 — Discovered while building.** Surfaced from a consistency check while labelling the
fee column, not from reading the schema: the two fields are equal to the last decimal on
every row, which is only possible if fees are excluded.

---

## 7. No order type, time-in-force, or limit validity

**1 — Behaviour blocked.** The screen shows a limit band with no instruction for how to
work it. A reader cannot tell whether this is a day limit, a marketable limit, or a
band inside which any fill is acceptable; whether to split the 563-share buy; or when
the band expires. An execution list that does not say how to execute is a worksheet.

**2 — Payload wanted.**

```json
{
  "instrument_id": "inst-aggs",
  "order_type": "LMT",
  "time_in_force": "DAY",
  "limit_valid_until": "2026-09-18T21:00:00Z",
  "routing_hint": "SMART",
  "max_participation_pct": 10.0
}
```

**3 — Acceptance criterion.** Every order carries `order_type` from a closed set
(`LMT`, `MKT`, `MOC`) and `time_in_force` from a closed set (`DAY`, `GTC`, `IOC`); an
`LMT` order also carries `limit_valid_until`. A test asserts membership per order.

**4 — Discovered while building.** Surfaced when the column set was complete and the
row still did not answer "and then what?". The brief's list of columns is the state of
the trade, not the instruction for it.

---

## 8. `integrity_evidence` is absent from the stored report

**1 — Behaviour blocked.** The screen cannot show what the list was computed *from*: no
statement id, no price-snapshot hash, no ingest run. `statement_ids` on the envelope is
present and empty, `findings` is present and empty, and `integrity_evidence` is absent
entirely — three different states, and the "Pre-flight checks" panel renders them as
three different things on purpose. The reader gets `content_hash` for the report and
nothing about its inputs, so "is this list built on today's statement?" is unanswerable
on the page.

**2 — Payload wanted.**

```json
{
  "integrity_evidence": {
    "statement_ids": ["stmt-2026-09-17"],
    "flex_run_id": "run-9c1e",
    "price_snapshot_hash": "9f2c…",
    "preflight": {"status": "pass", "checks_run": 12, "acknowledged_breaches": []}
  }
}
```

**3 — Acceptance criterion.** A report retrieved through `dion report` (i.e. through
persistence, not from the in-memory dataclass) has a non-empty `integrity_evidence`
whose `statement_ids` equal the envelope's `statement_ids`. A test asserts the key
survives store-then-retrieve; today
`tests/design_seed_pilot/test_fixture_fidelity.py::test_persistence_dropped_fields_are_absent`
asserts the opposite, and pins the loss.

**4 — Known before starting.** `test_fixture_fidelity.py` documents `comparators` and
`integrity_evidence` as "live in memory and lost on store".

---

## 9. `metric_comparison` has no `current` block

**1 — Behaviour blocked.** The "Proposed vs current risk" panel has an entirely missing
Current column: nine metrics, nine `—`. The envelope carries the proposed portfolio's
Sharpe, CVaR 95, CDaR 95, max drawdown, Ulcer, Martin, turnover and fees, and nothing to
compare them against — so the panel cannot answer the only question it exists to answer,
which is whether the proposal is better than what the reader already holds. The same
persistence boundary that drops `integrity_evidence` drops `comparators`.

**2 — Payload wanted.** `metric_comparison.current` mirroring `metric_comparison.proposed`
key for key:

```json
{
  "metric_comparison": {
    "current":  {"sharpe_ratio": 0.2814, "cvar_95": -0.0231, "cdar_95": -0.0309, "max_drawdown": -0.0472},
    "proposed": {"sharpe_ratio": 0.3414, "cvar_95": -0.0176, "cdar_95": -0.0241, "max_drawdown": -0.0335}
  }
}
```

**3 — Acceptance criterion.** In a stored envelope, `set(metric_comparison["current"])
== set(metric_comparison["proposed"])` and every value is a finite float. A test asserts
key-set equality and fails today on a missing `current`.

**4 — Known before starting.** Same source as §8 — the name `metric_comparison` with a
single `proposed` block is visible on a first read.

---

## 10. No account identifier

**1 — Behaviour blocked.** The screen cannot say whose account these orders are for.
`portfolio_state` has a position count and a total value; the envelope has
`statement_ids: []`. On a single-account cockpit that is survivable; on a printed or
shared list it is not, and there is nothing to caption a page or reconcile against a
broker ticket with.

**2 — Payload wanted.**

```json
{"account": {"account_id": "U1234567", "base_currency": "CHF", "analysis_currency": "CHF"}}
```

**3 — Acceptance criterion.** Every report envelope carries `account.account_id` as a
non-empty string. A test asserts presence and non-emptiness.

**4 — Discovered while building.** Surfaced building the "Portfolio before the trade"
panel: every other fact on the panel had a subject and the panel itself had none.

---

## Not a gap: states the envelope distinguishes correctly

Recorded because a contract delta that only lists absences misrepresents the envelope,
and because these are what the screen's three-state rendering is calibrated against.

- `fx_exposure.fx_risk_proxy` is `0.0` — a real zero, rendered as `0.0000` in normal
  text, not as `—`.
- `proposal_summary.suppressed_trades` is `0` — a real zero.
- `optimizer_summary.policy_violations` (`[]`) and `drift_analysis.snapshot_drift`
  (`{}`) are present and empty, rendered `present, empty`, which is distinct from
  `integrity_evidence`'s `— absent`.
- `run_review` cannot emit a value-level `null` anywhere in the envelope, so the
  missing-vs-zero distinction on this screen is carried entirely by *absent keys* and
  by the one documented empty-string fallback (§1).
