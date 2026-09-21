// execution_list.js — renders artifacts/execution-list.html from the embedded envelope.
//
// The ONLY data source is the application/json element with id "dion-report",
// which holds the report envelope verbatim. Nothing here fetches, and
// nothing here re-derives a number the backend already computed: a value the
// envelope does not supply is rendered as missing, with a reason, not as a sum
// invented on screen.
(function () {
  'use strict';

  var ENVELOPE = JSON.parse(document.getElementById('dion-report').textContent);
  var REPORT = (ENVELOPE.data || {}).report || {};
  var PROPOSAL = REPORT.proposal_summary || {};
  var ORDERS = PROPOSAL.orders || [];
  var CLASS = PROPOSAL.classifications || {};
  var GATES = (REPORT.fx_exposure || {}).review_gate_breaches || [];

  var MINUS = '−';
  var DASH = '—';

  // ---- formatting -------------------------------------------------------
  // Precision is a display decision, fixed per column, chosen once here.
  function group(digits) {
    var parts = digits.split('.');
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    return parts.join('.');
  }

  function fmt(value, dp, signed) {
    var abs = Math.abs(value).toFixed(dp);
    var sign = value < 0 ? MINUS : (signed ? '+' : '');
    return sign + group(abs);
  }

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) { node.className = cls; }
    if (text !== undefined && text !== null) { node.textContent = text; }
    return node;
  }

  // Missing is not zero and not empty: its own glyph, its own token, a reason.
  function missingCell(reason, inline) {
    var td = el('td', inline ? 'missing-inline' : 'missing', DASH);
    td.title = reason;
    return td;
  }

  function numCell(value, dp, signed, extraClass) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return missingCell('the envelope does not supply this value for this row');
    }
    var cls = 'num';
    if (extraClass) { cls += ' ' + extraClass; }
    var td = el('td', cls, fmt(value, dp, signed));
    td.title = String(value); // full source value survives the rounding
    return td;
  }

  function signedCell(value, dp) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return missingCell('the envelope does not supply this value for this row');
    }
    return numCell(value, dp, true, value > 0 ? 'pos' : (value < 0 ? 'neg' : ''));
  }

  function pill(kind, word) { return el('span', 'pill ' + kind, word); }

  // ---- header -----------------------------------------------------------
  function renderHeader() {
    var s = ENVELOPE.summary || {};
    document.getElementById('meta').textContent =
      'run ' + (ENVELOPE.run_id || DASH) + '  ·  report ' + (s.report_id || DASH) +
      '  ·  stored ' + (s.created_at || DASH) +
      '  ·  backend ' + ((REPORT.optimizer_summary || {}).chosen_backend || DASH);
  }

  // ---- gate banner ------------------------------------------------------
  function renderGate() {
    var host = document.getElementById('gate');
    if (!GATES.length) {
      host.appendChild(el('p', 'sub', 'No review-gate breach recorded on this envelope.'));
      return;
    }
    var box = el('div', 'banner');
    var h = el('h2', null, 'Blocked — ' + GATES.length + ' review-gate breach' +
      (GATES.length === 1 ? '' : 'es'));
    box.appendChild(h);
    box.appendChild(el('div', null,
      'Do not place these orders. Clear the gate in the review pipeline, or acknowledge ' +
      'the breach there, and regenerate. This screen is read-only and cannot clear it.'));
    var ul = document.createElement('ul');
    GATES.forEach(function (g) { ul.appendChild(el('li', null, g)); });
    box.appendChild(ul);
    host.appendChild(box);
  }

  // ---- orders -----------------------------------------------------------
  var COLUMNS = [
    ['Instrument', ''],
    ['Exchange', ''],
    ['Side', ''],
    ['Shares', 'num'],
    ['Limit low', 'num'],
    ['Limit high', 'num'],
    ['Order value', 'num'],
    ['Fee', 'num'],
    ['Current', 'num'],
    ['Post-trade', 'num'],
    ['Δ weight', 'num'],
    ['Cash Δ', 'num'],
    ['Status', '']
  ];
  var UNITS = ['', '', '', '#', 'local', 'local', 'local', 'CHF', '%', '%', 'pp', 'CHF', ''];

  function instrumentCell(order) {
    var td = document.createElement('td');
    if (order.symbol) {
      td.appendChild(el('span', 'mono', order.symbol));
    } else {
      var miss = el('span', 'missing-inline', DASH);
      miss.title = 'the envelope supplied an empty symbol ("") for this order — not a ' +
        'symbol-less instrument, a field the report could not resolve. There is no ticker ' +
        'to type into a broker ticket.';
      td.appendChild(miss);
    }
    td.appendChild(document.createElement('br'));
    td.appendChild(el('span', 'sub mono', order.instrument_id || DASH));
    return td;
  }

  function sideCell(order) {
    var buy = order.action === 'buy';
    // Colour AND a word AND a glyph: colour alone fails for ~1 in 12 men.
    var td = el('td', null);
    td.appendChild(el('span', buy ? 'pos' : 'neg',
      (buy ? '▲ Buy' : '▼ Sell')));
    return td;
  }

  function statusCell(order) {
    var td = document.createElement('td');
    if (GATES.length) { td.appendChild(pill('block', 'Gate blocked')); }
    if (!order.symbol) {
      var p = pill('warn', 'No symbol');
      p.title = 'cannot be placed as written: no ticker';
      td.appendChild(document.createTextNode(' '));
      td.appendChild(p);
    }
    if (!td.childNodes.length) { td.appendChild(pill('ok', 'Ready')); }
    return td;
  }

  function renderOrders() {
    var host = document.getElementById('orders');
    if (!ORDERS.length) {
      var box = el('div', 'card');
      box.appendChild(el('div', 'empty',
        'This report contains no proposed orders. Run `dion review` to produce a proposal.'));
      host.appendChild(box);
      return;
    }

    var card = el('div', 'card');
    var table = document.createElement('table');

    var cur = ORDERS[0].currency || 'local';
    var ccy = ORDERS[0].analysis_currency || 'CHF';
    var caption = el('caption', null,
      'Proposed orders — limits and order value in ' + cur + ' (the listing currency), ' +
      'fees and cash in ' + ccy + ' (the analysis currency). Weights in %, Δ in ' +
      'percentage points. Precision is fixed per column; hover a figure for the ' +
      'unrounded source value.');
    table.appendChild(caption);

    var thead = document.createElement('thead');
    var hr = document.createElement('tr');
    COLUMNS.forEach(function (c, i) {
      var th = el('th', c[1]);
      th.appendChild(document.createTextNode(c[0]));
      if (UNITS[i]) {
        th.appendChild(document.createElement('br'));
        th.appendChild(el('span', 'sub', UNITS[i] === '#' ? '#' : UNITS[i] === 'local' ? cur : UNITS[i]));
      }
      hr.appendChild(th);
    });
    thead.appendChild(hr);
    table.appendChild(thead);

    var tbody = document.createElement('tbody');
    ORDERS.forEach(function (o) {
      var c = CLASS[o.instrument_id] || {};
      var tr = document.createElement('tr');
      tr.appendChild(instrumentCell(o));
      tr.appendChild(el('td', null, o.exchange || DASH));
      tr.appendChild(sideCell(o));
      tr.appendChild(numCell(o.shares, 0));
      tr.appendChild(numCell(o.limit_low, 4));
      tr.appendChild(numCell(o.limit_high, 4));
      tr.appendChild(numCell(o.estimated_value_local, 2));
      tr.appendChild(numCell(o.expected_fee_chf, 2));
      tr.appendChild(typeof c.current_weight === 'number'
        ? numCell(c.current_weight * 100, 2)
        : missingCell('no classification row for this instrument in the envelope'));
      tr.appendChild(numCell(o.post_trade_weight * 100, 2));
      tr.appendChild(typeof c.weight_delta === 'number'
        ? signedCell(c.weight_delta * 100, 2)
        : missingCell('no classification row for this instrument in the envelope'));
      tr.appendChild(signedCell(o.cash_delta_chf, 2));
      tr.appendChild(statusCell(o));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);

    // Totals come from the envelope. The net cash delta is NOT in the envelope,
    // and summing the column here would be a number the backend never computed.
    var diag = (REPORT.optimizer_summary || {}).diagnostics || {};
    var tfoot = document.createElement('tfoot');
    var fr = document.createElement('tr');
    var lab = el('td', null, ORDERS.length + ' orders · totals as supplied');
    lab.colSpan = 7;
    fr.appendChild(lab);
    fr.appendChild(numCell(diag.estimated_fees, 2));
    var spacer = el('td', null, '');
    spacer.colSpan = 3;
    fr.appendChild(spacer);
    fr.appendChild(missingCell(
      'the envelope supplies no net cash delta, and no cash balance to apply it to. ' +
      'The column is not summed here: a UI-derived total would be a second, ' +
      'independently rounded number the backend never produced.'));
    fr.appendChild(el('td', null, ''));
    tfoot.appendChild(fr);
    table.appendChild(tfoot);

    card.appendChild(table);
    host.appendChild(card);

    var note = el('p', 'sub',
      'Gross traded value ' + fmt(PROPOSAL.total_trade_value, 2, false) + ' ' + ccy +
      '  ·  turnover ' + fmt((diag.turnover || 0) * 100, 2, false) + '%' +
      '  ·  suppressed trades ' + PROPOSAL.suppressed_trades +
      '  ·  cash deltas exclude the expected fee (each order’s |cash Δ| equals ' +
      'its estimated value in ' + ccy + '; the fee sits in its own column).');
    host.appendChild(note);
  }

  // ---- context panels ---------------------------------------------------
  function factList(rows) {
    var dl = el('dl', 'facts');
    rows.forEach(function (r) {
      dl.appendChild(el('dt', null, r[0]));
      if (r[1] === null) {
        var dd = el('dd', 'missing-inline', DASH);
        dd.title = r[2] || 'not supplied by this envelope';
        dl.appendChild(dd);
      } else {
        dl.appendChild(el('dd', null, r[1]));
      }
    });
    return dl;
  }

  function card(title, body) {
    var wrap = document.createElement('div');
    wrap.appendChild(el('h3', null, title));
    var c = el('div', 'card');
    c.appendChild(body);
    wrap.appendChild(c);
    return wrap;
  }

  function renderContext() {
    var host = document.getElementById('context');
    var state = REPORT.portfolio_state || {};
    var fx = REPORT.fx_exposure || {};
    var elig = REPORT.eligibility_summary || {};
    var opt = REPORT.optimizer_summary || {};
    var diag = opt.diagnostics || {};
    var drift = REPORT.drift_analysis || {};
    var ccy = (ORDERS[0] || {}).analysis_currency || 'CHF';

    host.appendChild(card('Portfolio before the trade', factList([
      ['Total value (' + ccy + ')', fmt(state.total_value, 2, false)],
      ['Positions', String(state.positions)],
      ['Cash balance', null, 'the envelope carries no cash balance, so the post-trade cash ' +
        'position cannot be shown'],
      ['Account', null, 'the envelope carries no account identifier'],
      ['Prices as of', null, 'the envelope carries no price/quote timestamp, so the age of ' +
        'the limit bands is unknown on this screen'],
      ['Max drift (%)', fmt(drift.drift_max_pct, 2, false)]
    ])));

    host.appendChild(card('Proposed vs current risk', (function () {
      var t = document.createElement('table');
      var th = document.createElement('thead');
      var r = document.createElement('tr');
      r.appendChild(el('th', null, 'Metric'));
      r.appendChild(el('th', 'num', 'Current'));
      r.appendChild(el('th', 'num', 'Proposed'));
      th.appendChild(r);
      t.appendChild(th);
      var tb = document.createElement('tbody');
      var mc = REPORT.metric_comparison || {};
      var current = mc.current || null;
      [['Annualised return', 'annualized_return', 4],
       ['Sharpe ratio', 'sharpe_ratio', 4],
       ['CVaR 95', 'cvar_95', 4],
       ['CDaR 95', 'cdar_95', 4],
       ['Max drawdown', 'max_drawdown', 4],
       ['Ulcer index', 'ulcer_index', 4],
       ['Martin ratio', 'martin_ratio', 4],
       ['Turnover', 'turnover', 4],
       ['Estimated fees (' + ccy + ')', 'estimated_fees', 2]
      ].forEach(function (m) {
        var tr = document.createElement('tr');
        tr.appendChild(el('td', null, m[0]));
        tr.appendChild(current
          ? numCell(current[m[1]], m[2])
          : missingCell('metric_comparison carries only a "proposed" block: the current ' +
              'portfolio’s comparators are dropped when the report is stored, so there ' +
              'is nothing to compare against.'));
        tr.appendChild(numCell((mc.proposed || diag)[m[1]], m[2]));
        tb.appendChild(tr);
      });
      t.appendChild(tb);
      return t;
    })()));

    var fxRows = [];
    Object.keys(fx.by_currency || {}).forEach(function (k) {
      fxRows.push([k + ' exposure (%)', fmt(fx.by_currency[k] * 100, 2, false)]);
    });
    fxRows.push(['Gross non-base (%)', fmt(fx.gross_non_base * 100, 2, false)]);
    fxRows.push(['FX risk proxy', fmt(fx.fx_risk_proxy, 4, false)]);
    fxRows.push(['FX rate used', null, 'the envelope reports each order in both the listing ' +
      'and the analysis currency but never states the rate that connects them, so the ' +
      'conversion cannot be checked here']);
    host.appendChild(card('FX exposure', factList(fxRows)));

    host.appendChild(card('Eligibility', factList([
      ['Eligible', String(elig.eligible)],
      ['Restricted', String(elig.restricted)],
      ['Unknown', String(elig.unknown)],
      ['Total screened', String(elig.total)],
      ['Rule applied', ((elig.details || [])[0] || {}).rule_applied || DASH]
    ])));

    // Empty and absent are different outcomes and are shown differently.
    var checks = el('ul', 'plain');
    function checkLine(label, value, emptyIsGood) {
      var li = document.createElement('li');
      li.appendChild(document.createTextNode(label + ': '));
      if (value === undefined) {
        var a = el('span', 'missing-inline', DASH + ' absent');
        a.title = 'the key is not present in this envelope at all — which is not the ' +
          'same as present-and-empty';
        li.appendChild(a);
      } else if (Array.isArray(value) ? value.length === 0 : Object.keys(value).length === 0) {
        li.appendChild(pill(emptyIsGood ? 'ok' : 'neutral', 'present, empty'));
      } else {
        li.appendChild(pill('warn', String(Array.isArray(value) ? value.length : Object.keys(value).length) + ' entries'));
      }
      checks.appendChild(li);
    }
    checkLine('Policy violations', opt.policy_violations, true);
    checkLine('Snapshot drift', drift.snapshot_drift, true);
    checkLine('Findings on the envelope', ENVELOPE.findings, true);
    checkLine('Statement ids', ENVELOPE.statement_ids, false);
    checkLine('Integrity evidence', REPORT.integrity_evidence);
    checkLine('Comparators', REPORT.comparators);
    host.appendChild(card('Pre-flight checks', checks));
  }

  // ---- action items -----------------------------------------------------
  function renderActions() {
    var host = document.getElementById('actions');
    var items = REPORT.action_items || [];
    var c = el('div', 'card');
    if (!items.length) {
      c.appendChild(el('div', 'empty', 'The report raised no action items.'));
      host.appendChild(c);
      return;
    }
    var ul = el('ul', 'plain');
    var kind = { buy: 'neutral', sell: 'neutral', fx_warning: 'warn', fx_review_gate: 'block' };
    items.forEach(function (it) {
      var li = document.createElement('li');
      li.appendChild(pill(kind[it.type] || 'neutral', it.type.replace(/_/g, ' ')));
      li.appendChild(document.createTextNode(' ' + it.description));
      if (it.instrument_id) {
        li.appendChild(document.createTextNode(' '));
        li.appendChild(el('span', 'sub mono', it.instrument_id));
      }
      ul.appendChild(li);
    });
    c.appendChild(ul);
    host.appendChild(c);
  }

  // ---- what this screen could not show ----------------------------------
  var GAPS = [
    ['Ticker for two of the five orders',
     'proposal_summary.orders[].symbol is "" for inst-aggs and inst-puls, so those rows ' +
     'cannot be typed into a broker ticket. Rendered as missing, not as a blank.'],
    ['Price as-of / quote timestamp',
     'Nothing in the envelope dates the limit bands, so the screen cannot tell a reader ' +
     'whether they are minutes or days old.'],
    ['The FX rate behind every CHF figure',
     'Orders carry a local and an analysis value but not the rate joining them.'],
    ['Current and post-trade share counts',
     'Only weights are supplied, so the screen cannot show "hold 200 → 763" or let a ' +
     'reader check the fill against the position.'],
    ['Net cash effect of the list',
     'No aggregate cash delta and no cash balance, so the totals row leaves it missing ' +
     'rather than summing a column the backend never summed.'],
    ['Current-portfolio risk comparators',
     'metric_comparison has only a "proposed" block, so the comparison table has an ' +
     'empty Current column.'],
    ['Order type, time-in-force, limit validity',
     'A limit band is supplied with no instruction for how it should be worked.'],
    ['Provenance of the numbers',
     'integrity_evidence is absent from the stored report, so the screen cannot show what ' +
     'statement or price snapshot the list was computed from.']
  ];

  function renderGaps() {
    var host = document.getElementById('gaps');
    var c = el('div', 'card');
    GAPS.forEach(function (g) {
      var d = el('div', 'gap');
      d.appendChild(el('strong', null, g[0]));
      d.appendChild(el('p', null, g[1]));
      c.appendChild(d);
    });
    host.appendChild(c);
  }

  // ---- theme ------------------------------------------------------------
  document.getElementById('theme').addEventListener('click', function () {
    var r = document.documentElement;
    r.setAttribute('data-theme', r.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
  });

  renderHeader();
  renderGate();
  renderOrders();
  renderContext();
  renderActions();
  renderGaps();
})();
