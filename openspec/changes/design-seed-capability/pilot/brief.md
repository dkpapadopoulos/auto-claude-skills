# Task brief

Build a read-only execution-list screen from the frozen report envelope at
`tests/fixtures/design_seed_pilot/review_report_envelope.json`.

## What to build

A Python generation step that reads the envelope and writes ONE self-contained
HTML file to `artifacts/execution-list.html`.

- The HTML must be openable directly from disk. No network requests, no
  `fetch`, no remote stylesheets, fonts, or scripts.
- Embed the complete envelope VERBATIM in exactly one element:
  `<script type="application/json" id="dion-report">`. Render from it.
- The generator lives under `scripts/` and must pass the repo's gate
  (`bash scripts/ci.sh`).

## What the screen shows

The proposed orders: instrument symbol, exchange, direction, share count, the
suggested limit band, expected fee, post-trade weight, and the signed cash
delta. Plus whatever context you judge a reader needs to act on it.

## Hard constraints

- The envelope is the ONLY data source. Do not read `data/`, do not open a
  database, do not reach the network.
- Do not change existing repository behaviour. This is additive.
- Do not "fix" the data on the way to the screen. If the envelope cannot
  support something the screen needs, record it (see below) and render what is
  actually there.

## Also produce: a contract delta

`artifacts/contract-delta.md`. For each field or representation the screen
needed but the envelope could not supply:

1. the specific screen behaviour that could not be built,
2. an example payload showing the shape you would want,
3. a testable acceptance criterion for the change,
4. whether you knew this before starting or discovered it while building — and,
   if discovered, what surfaced it.

## Done means

`bash scripts/ci.sh` passes, `artifacts/execution-list.html` opens from disk and
renders, and `artifacts/contract-delta.md` exists.
