#!/usr/bin/env python3
"""Render the frozen review-report envelope into a standalone execution-list screen.

Read-only and additive: the envelope JSON is the single data source. No DuckDB, no
`data/`, no network — at build time or at view time. The whole envelope is embedded
verbatim in one `<script type="application/json" id="dion-report">` element and the
page renders itself from that text, so the HTML file carries its own provenance and
can be diffed against the source fixture byte for byte.

Usage:
    uv run python scripts/build_execution_list.py
    uv run python scripts/build_execution_list.py --envelope <path> --out <path>
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ENVELOPE = (
    REPO_ROOT / "tests" / "fixtures" / "design_seed_pilot" / "review_report_envelope.json"
)
DEFAULT_OUTPUT = REPO_ROOT / "artifacts" / "execution-list.html"

# A JSON payload is safe inside <script type="application/json"> unless it can close the
# element or open a comment. The envelope is embedded verbatim, so we refuse rather than
# rewrite: silently escaping would break the byte-for-byte guarantee the screen relies on.
_UNSAFE_IN_SCRIPT = re.compile(r"</\s*script|<!--", re.IGNORECASE)


class EnvelopeNotEmbeddable(ValueError):
    """The envelope text cannot be embedded verbatim in an HTML script element."""


def assert_embeddable(envelope_text: str) -> None:
    """Fail closed if the envelope cannot go into the page unmodified."""
    match = _UNSAFE_IN_SCRIPT.search(envelope_text)
    if match is not None:
        raise EnvelopeNotEmbeddable(
            f"envelope contains {match.group(0)!r} at offset {match.start()}, which would "
            "terminate the embedding <script> element; it cannot be embedded verbatim"
        )


def build_html(envelope_text: str) -> str:
    """Return the full self-contained HTML document for `envelope_text`."""
    json.loads(envelope_text)  # structural gate: refuse to ship a page that cannot parse
    assert_embeddable(envelope_text)
    return _TEMPLATE.replace("__ENVELOPE_JSON__", envelope_text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--envelope", type=Path, default=DEFAULT_ENVELOPE, help="report envelope JSON"
    )
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT, help="HTML file to write")
    args = parser.parse_args(argv)

    envelope_text = args.envelope.read_text(encoding="utf-8")
    html = build_html(envelope_text)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(html, encoding="utf-8")
    print(f"wrote {args.out} ({len(html):,} bytes) from {args.envelope}")
    return 0


_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dion — Execution List</title>
<style>
  :root {
    --bg: #0f1115; --panel: #171a21; --panel-2: #1d212a; --line: #2a2f3a;
    --ink: #e6e9ef; --ink-dim: #9aa3b2; --ink-faint: #6b7483;
    --buy: #4ea1ff; --sell: #f0a44a; --bad: #ff6b6b; --warn: #ffc857; --ok: #5ac888;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 28px 32px 64px; background: var(--bg); color: var(--ink);
    font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  h1 { font-size: 20px; margin: 0 0 2px; letter-spacing: .01em; }
  h2 { font-size: 12px; text-transform: uppercase; letter-spacing: .09em; color: var(--ink-dim);
       margin: 0 0 10px; font-weight: 600; }
  .sub { color: var(--ink-dim); font-size: 12.5px; margin-bottom: 18px; }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-variant-numeric: tabular-nums; }
  .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 16px 18px; margin-bottom: 16px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(270px, 1fr)); gap: 16px; align-items: start; }
  .grid .panel { margin-bottom: 0; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 8px 10px; text-align: right; border-bottom: 1px solid var(--line); white-space: nowrap; }
  th { font-size: 11px; text-transform: uppercase; letter-spacing: .06em; color: var(--ink-dim); font-weight: 600; border-bottom-color: #3a4050; }
  th.l, td.l { text-align: left; }
  tbody tr:hover { background: var(--panel-2); }
  tfoot td { font-weight: 600; border-bottom: none; border-top: 2px solid #3a4050; }
  .sym { font-weight: 700; font-size: 15px; letter-spacing: .02em; }
  .side { display: inline-block; min-width: 46px; text-align: center; padding: 2px 8px; border-radius: 5px;
          font-size: 11px; font-weight: 700; letter-spacing: .07em; }
  .side.buy { background: rgba(78,161,255,.15); color: var(--buy); border: 1px solid rgba(78,161,255,.4); }
  .side.sell { background: rgba(240,164,74,.15); color: var(--sell); border: 1px solid rgba(240,164,74,.4); }
  .pos { color: var(--ok); } .neg { color: var(--sell); }
  .dim { color: var(--ink-dim); } .faint { color: var(--ink-faint); }
  .missing { color: var(--bad); font-style: italic; font-weight: 600; }
  tr.flagged td:first-child { box-shadow: inset 3px 0 0 var(--bad); }
  .banner { border-radius: 10px; padding: 13px 16px; margin-bottom: 16px; border: 1px solid; }
  .banner.block { background: rgba(255,107,107,.09); border-color: rgba(255,107,107,.45); }
  .banner.warn { background: rgba(255,200,87,.08); border-color: rgba(255,200,87,.4); }
  .banner .t { font-weight: 700; letter-spacing: .03em; margin-bottom: 5px; }
  .banner.block .t { color: var(--bad); } .banner.warn .t { color: var(--warn); }
  .banner ul { margin: 4px 0 0; padding-left: 20px; }
  .banner li { margin: 2px 0; }
  dl { margin: 0; display: grid; grid-template-columns: auto 1fr; gap: 5px 14px; }
  dt { color: var(--ink-dim); font-size: 12.5px; }
  dd { margin: 0; text-align: right; font-variant-numeric: tabular-nums; }
  .note { font-size: 12px; color: var(--ink-faint); margin-top: 10px; line-height: 1.5; }
  .band { font-size: 12.5px; }
  .band .w { color: var(--ink-faint); font-size: 11.5px; }
  .pill { font-size: 10.5px; padding: 1px 6px; border-radius: 4px; border: 1px solid var(--line); color: var(--ink-dim); }
  ul.plain { margin: 0; padding-left: 18px; }
  ul.plain li { margin: 3px 0; }
  footer { color: var(--ink-faint); font-size: 11.5px; margin-top: 26px; border-top: 1px solid var(--line); padding-top: 12px; }
</style>
</head>
<body>
<main id="app"><noscript>This screen renders the embedded report envelope with JavaScript; enable it to view.</noscript></main>

<script type="application/json" id="dion-report">
__ENVELOPE_JSON__
</script>

<script>
(function () {
  "use strict";
  var env = JSON.parse(document.getElementById("dion-report").textContent);
  var app = document.getElementById("app");
  var report = (env.data && env.data.report) || {};
  var summary = env.summary || {};
  var proposal = report.proposal_summary || {};
  var orders = proposal.orders || [];
  var classifications = proposal.classifications || {};
  var optimizer = report.optimizer_summary || {};
  var fx = report.fx_exposure || {};
  var state = report.portfolio_state || {};
  var metrics = (report.metric_comparison || {}).proposed || optimizer.diagnostics || {};
  var eligibility = report.eligibility_summary || {};
  var actions = report.action_items || [];
  var ccy = (orders[0] || {}).analysis_currency || "";

  // ---- formatting helpers -------------------------------------------------
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }
  function has(v) { return v !== undefined && v !== null && v !== ""; }
  function num(v, dp) {
    if (typeof v !== "number" || !isFinite(v)) return null;
    return v.toLocaleString("en-US", { minimumFractionDigits: dp, maximumFractionDigits: dp });
  }
  function pct(v, dp) {
    if (typeof v !== "number" || !isFinite(v)) return "—";
    return (v * 100).toFixed(dp === undefined ? 2 : dp) + "%";
  }
  function signed(v, dp) {
    var s = num(Math.abs(v), dp === undefined ? 2 : dp);
    if (s === null) return "—";
    return (v < 0 ? "−" : "+") + s;
  }
  function cell(row, cls, text) { var td = el("td", cls, text); row.appendChild(td); return td; }

  // ---- gaps found in the data itself, not assumed -------------------------
  var gaps = [];
  var missingSymbol = orders.filter(function (o) { return !has(o.symbol); });
  if (missingSymbol.length) {
    gaps.push(missingSymbol.length + " of " + orders.length + " orders carry an empty `symbol`: " +
      missingSymbol.map(function (o) { return o.instrument_id; }).join(", ") +
      ". They cannot be identified on a broker ticket from this envelope.");
  }
  if (!(report.metric_comparison || {}).current) {
    gaps.push("`metric_comparison` contains only `proposed` — there is no current-portfolio baseline, " +
      "so the risk/return effect of trading cannot be shown as a before → after change.");
  }
  if (!has(state.currency)) {
    gaps.push("`portfolio_state.total_value` (" + num(state.total_value, 2) + ") carries no currency field; " +
      "it is displayed as " + (ccy || "the analysis currency") + " by inference from the orders.");
  }
  if (!has(summary.market_data_as_of) && !has(proposal.priced_as_of)) {
    gaps.push("No as-of timestamp for the prices behind the limit bands — staleness is unknowable from the envelope.");
  }
  if (orders.some(function (o) { return !has(o.fx_rate); })) {
    gaps.push("No FX rate field: local↔analysis conversion is shown as an implied rate derived from " +
      "`estimated_value_local / estimated_value_analysis`.");
  }
  if (!Array.isArray(proposal.suppressed_trades)) {
    gaps.push("`suppressed_trades` is a bare count (" + proposal.suppressed_trades + ") with no per-trade " +
      "detail, so what was deliberately not proposed cannot be shown.");
  }
  if (!(env.statement_ids || []).length && state.positions) {
    gaps.push("`statement_ids` is empty although " + state.positions + " positions are reported — the screen " +
      "cannot name the statement the current weights came from.");
  }
  if (!has(proposal.execution_status) && (fx.review_gate_breaches || []).length) {
    gaps.push("Review-gate breaches are present but no field states whether the proposal is cleared to execute; " +
      "the banner below is inferred from `fx_exposure.review_gate_breaches` being non-empty.");
  }

  // ---- header -------------------------------------------------------------
  app.appendChild(el("h1", null, "Execution list — " + (summary.report_id || env.run_id || "report")));
  var sub = el("div", "sub");
  sub.appendChild(el("span", "mono", "run " + (env.run_id || "—")));
  sub.appendChild(document.createTextNode("  ·  built " + (summary.created_at || "—")));
  sub.appendChild(document.createTextNode("  ·  backend " + (optimizer.chosen_backend || "—")));
  sub.appendChild(document.createTextNode("  ·  analysis currency " + (ccy || "—")));
  app.appendChild(sub);

  // ---- blocking / warning banners ----------------------------------------
  function banner(kind, title, items) {
    if (!items || !items.length) return;
    var b = el("div", "banner " + kind);
    b.appendChild(el("div", "t", title));
    var ul = el("ul");
    items.forEach(function (t) { ul.appendChild(el("li", null, t)); });
    b.appendChild(ul);
    app.appendChild(b);
  }
  banner("block", "Review gate breached — do not execute without sign-off", fx.review_gate_breaches || []);
  banner("warn", "Warnings", fx.warnings || []);
  banner("warn", "Policy violations", optimizer.policy_violations || []);
  if (missingSymbol.length) {
    banner("block", "Orders not ticketable as delivered", missingSymbol.map(function (o) {
      return o.instrument_id + ": " + String(o.action).toUpperCase() + " " + num(o.shares, 0) +
        " on " + (o.exchange || "—") + " has no symbol in the envelope.";
    }));
  }

  // ---- orders table -------------------------------------------------------
  var panel = el("div", "panel");
  panel.appendChild(el("h2", null, "Proposed orders (" + orders.length + ")"));
  var table = el("table");
  var thead = el("thead"), hr = el("tr");
  [["Symbol", "l"], ["Exchange", "l"], ["Side", "l"], ["Shares", ""], ["Limit band", ""],
   ["Est. value", ""], ["Fee " + ccy, ""], ["Weight → post-trade", ""], ["Cash Δ " + ccy, ""]]
    .forEach(function (h) { hr.appendChild(el("th", h[1], h[0])); });
  thead.appendChild(hr);
  table.appendChild(thead);

  var tbody = el("tbody");
  var totalFee = 0, netCash = 0, totalGross = 0;
  orders.forEach(function (o) {
    var tr = el("tr");
    if (!has(o.symbol)) tr.className = "flagged";

    var c0 = cell(tr, "l");
    if (has(o.symbol)) {
      c0.appendChild(el("div", "sym", o.symbol));
    } else {
      c0.appendChild(el("div", "sym missing", "no symbol"));
    }
    c0.appendChild(el("div", "faint mono", o.instrument_id || "—"));

    cell(tr, "l", o.exchange || "—");

    var side = cell(tr, "l");
    var isBuy = String(o.action).toLowerCase() === "buy";
    side.appendChild(el("span", "side " + (isBuy ? "buy" : "sell"), String(o.action || "?").toUpperCase()));

    cell(tr, "mono", num(o.shares, 0) || "—");

    var band = cell(tr, "mono band");
    if (typeof o.limit_low === "number" && typeof o.limit_high === "number") {
      band.appendChild(el("div", null, num(o.limit_low, 4) + " – " + num(o.limit_high, 4) + " " + (o.currency || "")));
      var mid = (o.limit_low + o.limit_high) / 2;
      var bps = mid ? ((o.limit_high - mid) / mid) * 10000 : 0;
      band.appendChild(el("div", "w", "mid " + num(mid, 4) + " ± " + num(bps, 0) + " bps"));
    } else {
      band.appendChild(el("span", "missing", "—"));
    }

    var val = cell(tr, "mono");
    val.appendChild(el("div", null, num(o.estimated_value_local, 2) + " " + (o.currency || "")));
    var implied = (typeof o.estimated_value_analysis === "number" && o.estimated_value_analysis)
      ? o.estimated_value_local / o.estimated_value_analysis : null;
    val.appendChild(el("div", "w faint",
      num(o.estimated_value_analysis, 2) + " " + (o.analysis_currency || "") +
      (implied ? "  @ " + num(implied, 5) + " implied" : "")));

    cell(tr, "mono", num(o.expected_fee_chf, 2) || "—");

    var cls = classifications[o.instrument_id] || {};
    var w = cell(tr, "mono");
    w.appendChild(el("div", null, pct(cls.current_weight) + " → " + pct(o.post_trade_weight)));
    if (typeof cls.weight_delta === "number") {
      w.appendChild(el("div", "w " + (cls.weight_delta >= 0 ? "pos" : "neg"),
        signed(cls.weight_delta * 100, 2) + " pp · " + (cls.action || "")));
    }

    cell(tr, "mono " + (o.cash_delta_chf >= 0 ? "pos" : "neg"), signed(o.cash_delta_chf, 2));

    tbody.appendChild(tr);
    totalFee += (typeof o.expected_fee_chf === "number" ? o.expected_fee_chf : 0);
    netCash += (typeof o.cash_delta_chf === "number" ? o.cash_delta_chf : 0);
    totalGross += Math.abs(typeof o.cash_delta_chf === "number" ? o.cash_delta_chf : 0);
  });
  table.appendChild(tbody);

  var tfoot = el("tfoot"), fr = el("tr");
  cell(fr, "l", "Total").colSpan = 5;
  cell(fr, "mono", num(totalGross, 2) + " " + ccy + " gross");
  cell(fr, "mono", num(totalFee, 2));
  cell(fr, "l dim", "");
  cell(fr, "mono " + (netCash >= 0 ? "pos" : "neg"), signed(netCash, 2));
  tfoot.appendChild(fr);
  table.appendChild(tfoot);
  panel.appendChild(table);

  var note = el("div", "note");
  note.textContent = "Limit bands and estimated values are in each order's listing currency (" +
    (orders[0] || {}).currency + "); fees and cash deltas are in " + ccy +
    ". Cash Δ is signed from the account's perspective: negative funds a buy. " +
    "Envelope `total_trade_value` = " + num(proposal.total_trade_value, 2) + " " + ccy +
    "; suppressed trades = " + (proposal.suppressed_trades === undefined ? "—" : proposal.suppressed_trades) + ".";
  panel.appendChild(note);
  app.appendChild(panel);

  // ---- context panels -----------------------------------------------------
  function dl(pairs) {
    var d = el("dl");
    pairs.forEach(function (p) {
      if (p[1] === null || p[1] === undefined) return;
      d.appendChild(el("dt", null, p[0]));
      d.appendChild(el("dd", p[2] || "mono", p[1]));
    });
    return d;
  }
  function panelWith(title, node, footnote) {
    var p = el("div", "panel");
    p.appendChild(el("h2", null, title));
    p.appendChild(node);
    if (footnote) p.appendChild(el("div", "note", footnote));
    return p;
  }

  var grid = el("div", "grid");

  grid.appendChild(panelWith("Portfolio before trading", dl([
    ["Positions", String(state.positions === undefined ? "—" : state.positions)],
    ["Total value", num(state.total_value, 2) + " " + (state.currency || ccy + " (inferred)")],
    ["Net cash after orders", signed(netCash, 2) + " " + ccy],
    ["Fees", num(totalFee, 2) + " " + ccy],
    ["Turnover", pct(metrics.turnover)],
    ["Statements", (env.statement_ids || []).length ? (env.statement_ids || []).join(", ") : "none listed"],
  ]), has(state.currency) ? null : "Currency of `total_value` is inferred, not stated by the envelope."));

  grid.appendChild(panelWith("Proposed portfolio metrics", dl([
    ["Annualised return", pct(metrics.annualized_return)],
    ["Sharpe", num(metrics.sharpe_ratio, 3)],
    ["CVaR 95%", pct(metrics.cvar_95)],
    ["CDaR 95%", pct(metrics.cdar_95)],
    ["Max drawdown", pct(metrics.max_drawdown)],
    ["Ulcer index", num(metrics.ulcer_index, 4)],
    ["Martin ratio", num(metrics.martin_ratio, 3)],
    ["Estimated fees", num(metrics.estimated_fees, 2) + " " + ccy],
    ["Resampled", String(optimizer.diagnostics ? optimizer.diagnostics.resampled : "—")],
  ]), "Proposed figures only — the envelope carries no current-portfolio baseline to compare against."));

  var fxNode = dl(Object.keys(fx.by_currency || {}).map(function (k) {
    return [k + " exposure", pct(fx.by_currency[k], 1)];
  }).concat([
    ["Gross non-base", pct(fx.gross_non_base, 1)],
    ["FX risk proxy", num(fx.fx_risk_proxy, 4)],
  ]));
  grid.appendChild(panelWith("FX exposure", fxNode));

  var drift = (report.drift_analysis || {});
  var driftRows = Object.keys(drift.proposal_drift || {}).map(function (k) {
    var o = orders.filter(function (x) { return x.instrument_id === k; })[0] || {};
    return [(has(o.symbol) ? o.symbol : k), signed(drift.proposal_drift[k] * 100, 2) + " pp"];
  });
  grid.appendChild(panelWith("Drift vs proposal", dl(driftRows.concat([
    ["Max drift", num(drift.drift_max_pct, 2) + "%"],
    ["Snapshot drift", Object.keys(drift.snapshot_drift || {}).length ? "present" : "empty"],
  ])), "Envelope sign convention: `proposal_drift` is current − proposed, the negation of " +
       "`classifications.weight_delta` shown in the table. Both are rendered as given."));

  grid.appendChild(panelWith("Eligibility", dl([
    ["Total", String(eligibility.total === undefined ? "—" : eligibility.total)],
    ["Eligible", String(eligibility.eligible === undefined ? "—" : eligibility.eligible)],
    ["Restricted", String(eligibility.restricted === undefined ? "—" : eligibility.restricted)],
    ["Unknown", String(eligibility.unknown === undefined ? "—" : eligibility.unknown)],
    ["Rule", ((eligibility.details || [])[0] || {}).rule_applied || "—"],
  ])));

  var acts = el("ul", "plain");
  actions.forEach(function (a) {
    var li = el("li");
    li.appendChild(el("span", "pill", a.type));
    li.appendChild(document.createTextNode(" " + a.description));
    acts.appendChild(li);
  });
  grid.appendChild(panelWith("Action items (" + actions.length + ")", acts));

  if (gaps.length) {
    var gl = el("ul", "plain");
    gaps.forEach(function (g) { gl.appendChild(el("li", "dim", g)); });
    grid.appendChild(panelWith("Envelope gaps affecting this screen (" + gaps.length + ")", gl,
      "Detected from the embedded payload at render time, not hard-coded. See artifacts/contract-delta.md."));
  }

  app.appendChild(grid);

  var foot = el("footer");
  foot.textContent = "Read-only. Rendered entirely from the embedded envelope (" +
    (env.command || "?") + "/" + (env.run_type || "?") + ", ok=" + String(env.ok) +
    ", findings=" + ((env.findings || []).length) + "). content_hash " + (summary.content_hash || "—") +
    ". No network access, no database, nothing recomputed from outside the payload.";
  app.appendChild(foot);
})();
</script>
</body>
</html>
"""


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(main())
