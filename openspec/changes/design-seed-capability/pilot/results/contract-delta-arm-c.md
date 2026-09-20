# Contract delta — execution-list screen vs `review_report_envelope.json`

Source: `tests/fixtures/design_seed_pilot/review_report_envelope.json` (report
`rpt-a3ade10d6cf9`, run `rev-b7bd753c33f9`, content hash `3d8de6d0…4433`).
Screen: `artifacts/execution-list.html`, built by `scripts/build_execution_list.py`.

Nothing below was worked around in the renderer. Every gap is rendered as it actually
is — blank symbols show as `no symbol`, single-sided metrics are labelled as such — and
the screen re-derives this list from the embedded payload at view time, so the page and
this document cannot drift apart.

Ordered by how much each one blocks an operator actually placing the orders.

---

## 1. `orders[].symbol` is empty for 2 of 5 orders

**Screen behaviour that could not be built.** The execution list's primary identifier
column. `inst-aggs` (BUY 563 @ 59.1498–59.4463) and `inst-puls` (BUY 429 @
49.7514–50.0008) carry `"symbol": ""`. Those two rows — 48,208 CHF of buying, the entire
buy leg — cannot be typed into a broker ticket from this envelope. `instrument_id` is an
internal surrogate (`inst-aggs`), not a tradable identifier, and the envelope contains no
other route to one. The screen renders them flagged and raises a blocking banner rather
than guessing that `inst-aggs` means `AGGS`.

**Wanted payload.** Identity that is sufficient on its own, and never partially empty:

```json
{
  "instrument_id": "inst-aggs",
  "symbol": "AGGS",
  "identity": {
    "name": "iShares Core Global Aggregate Bond UCITS ETF",
    "isin": "IE00B3F81409",
    "ibkr_conid": 154025151,
    "primary_exchange": "ARCA",
    "listing_currency": "USD"
  }
}
```

**Acceptance criterion.** Given any report envelope whose `proposal_summary.orders` is
non-empty, every order has a non-empty `symbol` and a non-empty `identity.isin`;
a proposal that cannot resolve both for an instrument does not emit an order for it —
it emits it under a new `proposal_summary.unticketable[]` with a `reason`. Test: build
the envelope for a universe with one identifier-less instrument and assert the order
count drops by one and `unticketable[0].reason` names the missing field.

**Knew or discovered.** Discovered. Surfaced the moment the symbol column was rendered:
three rows had a ticker and two had an empty headline cell. Reading the fixture as JSON
beforehand did not surface it — `"symbol": ""` reads as present-and-fine in a payload
dump, and the eligibility block reports all five instruments `eligible`, which is exactly
the signal that would discourage a second look.

---

## 2. No FX rate, and no as-of, for the local ↔ analysis conversion

**Screen behaviour.** Each row mixes currencies: the limit band and
`estimated_value_local` are USD, while `expected_fee_chf` and `cash_delta_chf` are CHF.
An operator checking a fill against the expected cash movement needs the rate that was
used and when it was struck. The envelope has no rate field, so the screen displays an
*implied* rate (`estimated_value_local / estimated_value_analysis` ≈ 1.13636 USD/CHF),
labelled `implied`, with no timestamp.

**Wanted payload.**

```json
{
  "fx": {
    "pair": "USD/CHF",
    "rate": 0.88,
    "quote_convention": "analysis_per_local",
    "as_of": "2026-09-18T14:30:00Z",
    "source": "openbb_daily_close"
  }
}
```

**Acceptance criterion.** For every order where `currency != analysis_currency`,
`order.fx.rate` is present and
`abs(estimated_value_local * order.fx.rate - estimated_value_analysis) <= 0.01`;
where `currency == analysis_currency`, `fx.rate == 1.0`. Assert on the pilot fixture
and on a single-currency fixture.

**Knew or discovered.** Knew before starting — a screen that prices in one currency and
settles in another needs the rate on the face of it. What was *not* anticipated: that the
rate is recoverable by division, which makes the omission easy to paper over. The screen
deliberately marks the derived number rather than presenting it as a fact from the report.

---

## 3. No as-of for the prices behind the limit bands

**Screen behaviour.** A staleness indicator — "priced 18 Sep close, 2 days ago" — next
to the limit band, so the reader knows whether 59.1498–59.4463 is still a plausible
band before sending the order. Every band in this envelope is a symmetric ±25 bps
around an unnamed reference price (mid 59.2980 for `inst-aggs`, recoverable as
`estimated_value_local / shares`), but nothing dates that reference, and
`summary.created_at` dates the *report*, not the market data. The screen shows the mid
and the band width, and lists the missing as-of as a gap.

**Wanted payload.**

```json
{
  "pricing": {
    "reference_price": 59.2980,
    "band_bps": 25,
    "as_of": "2026-09-18T20:00:00Z",
    "price_type": "adjusted_close",
    "source": "openbb_daily"
  }
}
```

**Acceptance criterion.** Every order carries `pricing.as_of`; a renderer given an
envelope whose `pricing.as_of` is older than the policy's staleness window can mark
the row without consulting any other source. Test: two fixtures, one inside and one
outside the window, produce different rendered staleness states from the envelope alone.

**Knew or discovered.** Discovered, while deciding what to put under the limit band.
The reference price and the ±25 bps rule are both reconstructable from what is there,
which is what makes the absent timestamp conspicuous: the envelope carries the *shape*
of the pricing decision but not its vintage.

---

## 4. Nothing states whether the proposal is cleared to execute

**Screen behaviour.** The single most important thing on an execution screen: may this
be traded, yes or no. `fx_exposure.review_gate_breaches` has two entries (USD 98.8% over
a 50% gate; unhedged FX 98.8% over a 70% gate) and `action_items` repeats them as
`fx_review_gate`, yet the envelope's only status-like fields are `ok: true` (the *report
command* succeeded) and `summary.status: "found"` (the report was retrieved). The screen
therefore *infers* the block from `review_gate_breaches` being non-empty — an inference a
renderer should not be making.

**Wanted payload.**

```json
{
  "proposal_summary": {
    "execution_status": "blocked",
    "blocking_gates": [
      {"id": "fx.usd_exposure", "detail": "USD exposure 98.8% exceeds 50% gate",
       "acknowledged": false, "ack_id": null}
    ]
  }
}
```

**Acceptance criterion.** `execution_status` is one of `cleared|blocked|acknowledged`,
and is `blocked` whenever any gate evaluates to a breach, independent of which subsystem
raised it; an envelope with a non-empty `blocking_gates` and
`execution_status == "cleared"` fails validation. Mirrors the existing `--ack-breach`
model, so an acknowledged breach shows as `acknowledged` with its `ack_id`.

**Knew or discovered.** Discovered. The intent was simply to show a red banner; writing
the condition for it exposed that the only honest source was "a list of strings is not
empty", and that a second subsystem raising a gate tomorrow would silently not appear.

---

## 5. `metric_comparison` has no `current` side

**Screen behaviour.** A before → after column pair: "CVaR 95% −1.41% → −1.76%,
turnover 40.9% buys you this." `metric_comparison` contains only `proposed`, byte-identical
to `optimizer_summary.diagnostics`. With no baseline, a reader cannot tell whether
40.9% turnover and 53.82 CHF of fees purchase an improvement or a regression. The screen
renders a single-sided panel and says so.

**Wanted payload.**

```json
{
  "metric_comparison": {
    "current": {"cvar_95": -0.0141, "sharpe_ratio": 0.29, "max_drawdown": -0.0402},
    "proposed": {"cvar_95": -0.0176, "sharpe_ratio": 0.3414, "max_drawdown": -0.0335},
    "basis": {"lookback_days": 756, "as_of": "2026-09-18"}
  }
}
```

**Acceptance criterion.** `metric_comparison.current` and `.proposed` carry the same key
set, computed over the same `basis`; a review whose current weights equal its proposed
weights yields `current == proposed` for every key. That equality case is the cheap
regression test — it fails if the two sides are ever computed over different windows.

**Knew or discovered.** Discovered, from the field name. `metric_comparison` was read as
the before/after source; it turned out to be a one-sided alias of `diagnostics`.

---

## 6. `portfolio_state.total_value` has no currency, and there is no cash balance

**Screen behaviour.** Fundability: the buy leg needs 48,207.85 CHF before the sells
settle, and the screen cannot say whether the account holds it. There is no cash figure
at all, and `total_value: 119680.0` carries no currency tag — the screen labels it CHF by
inference from the orders' `analysis_currency`. Settlement timing (sell proceeds arriving
T+1 against same-day buys) is likewise unexpressible.

**Wanted payload.**

```json
{
  "portfolio_state": {
    "currency": "CHF",
    "total_value": 119680.0,
    "cash": {"CHF": 1204.55, "USD": 0.0},
    "buying_power": 1204.55
  }
}
```

**Acceptance criterion.** `portfolio_state.currency` is always present and equals every
order's `analysis_currency`; `cash` is keyed by currency and present even when zero
(absent ≠ zero). A renderer can then compare the sum of negative `cash_delta` against
`buying_power` without inference.

**Knew or discovered.** Half-and-half. The missing cash balance was expected —
`portfolio_state` announces `positions: 5` and nothing else. The *untagged* `total_value`
was discovered while writing the panel label, and is the sharper defect: it is a number
that looks complete.

---

## 7. `suppressed_trades` is a count with no detail

**Screen behaviour.** "3 trades suppressed (below minimum ticket)" as an expandable
list, so the reader knows what was deliberately not proposed. The envelope says
`suppressed_trades: 0`, which is fine here but unrenderable the moment it is non-zero:
there is no array to expand, no reason code, no instrument.

**Wanted payload.**

```json
{
  "suppressed_trades": [
    {"instrument_id": "inst-spmo", "symbol": "SPMO", "action": "sell", "shares": 3,
     "reason": "below_min_ticket", "detail": "355 CHF < 1000 CHF minimum"}
  ]
}
```

**Acceptance criterion.** `len(suppressed_trades)` equals the count previously reported,
and every entry names an `instrument_id` and a machine-readable `reason`. Test: a policy
with a minimum ticket size large enough to suppress one order produces exactly one entry
whose `reason` is `below_min_ticket`.

**Knew or discovered.** Discovered — as a zero. A count of zero hides that the field
cannot answer the question it implies; had this envelope suppressed anything, the screen
would have had a number with nothing behind it.

---

## 8. Sign conventions are implicit and locally inconsistent

**Screen behaviour.** Directional colouring and arrows on every signed number, without a
per-field lookup. Three conventions coexist without being declared anywhere in the
payload: `classifications[].weight_delta` is proposed − current (`inst-aggs`: +0.2457);
`drift_analysis.proposal_drift` is its exact negation (`inst-aggs`: −0.2457);
`cash_delta_chf` is account-perspective (negative funds a buy) while the co-located
`estimated_value_analysis` is unsigned. `drift_max_pct` is in percent (24.57) while every
neighbouring figure is a fraction. The screen renders each as given and states the
conventions in prose it had to derive by arithmetic.

**Wanted payload.** Either a declared convention block, or — better — consistent signs
plus units in the field name (`drift_max_fraction`):

```json
{
  "conventions": {
    "weight_delta": "proposed_minus_current",
    "proposal_drift": "current_minus_proposed",
    "cash_delta": "account_perspective_negative_funds_buy",
    "units": {"drift_max_pct": "percent", "weights": "fraction"}
  }
}
```

**Acceptance criterion.** For every instrument,
`proposal_drift[i] == -classifications[i].weight_delta` holds as an asserted invariant
(it holds in this envelope by coincidence of construction, not by contract), and every
`*_pct` field is a percent while every other ratio is a fraction. A schema test fails on
any new ratio field whose name and unit disagree.

**Knew or discovered.** Discovered, by cross-checking the drift panel against the orders
table and finding matched magnitudes with opposite signs — which reads as a bug until you
work out that both are correct under different conventions. That ambiguity is the defect.

---

## 9. No provenance link back to the statement the positions came from

**Screen behaviour.** "Positions as of IBKR statement `stmt-…`, loaded `run-…`" in the
header, so a reader can tell which snapshot the current weights describe.
`statement_ids` is `[]` and `drift_analysis.snapshot_drift` is `{}`, so the screen can
only print the report's own ids and `none listed`.

**Wanted payload.**

```json
{
  "statement_ids": ["stmt-20260918-U1234567"],
  "provenance": {
    "positions_as_of": "2026-09-18",
    "flex_run_id": "run-9f2c1a",
    "statement_content_hash": "9c1d…"
  }
}
```

**Acceptance criterion.** Any envelope whose `portfolio_state.positions > 0` has a
non-empty `statement_ids` and a `provenance.positions_as_of`; a pre-funding envelope
(`positions == 0`) may have both empty. That split keeps the documented pre-funding
cold-start path legal while closing the gap for a funded account.

**Knew or discovered.** Discovered. `statement_ids: []` alongside five live positions
worth 119,680 is the contradiction that surfaced it — the positions came from somewhere
the envelope does not name.

---

## Not gaps

Recorded so a later reader does not re-litigate them:

- **`limit_low`/`limit_high` have no currency tag of their own.** Resolvable — they are
  in `order.currency`, confirmed by `shares × mid == estimated_value_local`. Worth a
  field one day; not blocking.
- **No order type / time-in-force.** Out of scope: this is a read-only proposal screen,
  not an order-entry surface, and the limit band is the proposal's whole statement about
  execution style.
- **`findings: []` and `policy_violations: []`.** Genuinely empty, not missing; the
  screen renders no banner for them, which is correct.
