# Styleguide — quiet-dense (preset v1)

This file holds only what the lint **cannot** decide. Anything mechanically checkable
lives in `checks/token-lint.sh`; restating it here would be prose pretending to be a rule.

**Read `tokens.css` first.** It defines two kinds of token, and the difference is the
whole idea:

- **Scale** tokens (`--space-3`, `--text-md`) answer *how much*.
- **Role** tokens (`--text-numeric`, `--status-block-fg`) answer *what this is for*.

Reference roles. A closed set of values stops you inventing `#3B82F6`; only roles stop you
picking a value that is allowed but means the wrong thing.

## Numbers

Numbers are the reason this styleguide exists — most screens that feel untrustworthy are
mishandling them.

| Do | Don't |
|---|---|
| Set `font-variant-numeric: tabular-nums` and `--font-mono` on any column of figures | Let proportional digits make columns jitter as values change |
| Right-align numerals; left-align their labels | Centre-align numbers, ever |
| Keep decimal places **fixed per column**, chosen once | Vary precision row by row because the source varied |
| Show the unit or currency once, in the header | Repeat the unit on every cell |
| Colour direction with `--value-positive` / `--value-negative` **and** a sign or arrow | Rely on colour alone — it fails for ~1 in 12 men |

**Precision is a display decision, and it is lossy.** Round for the eye, keep the source
value for the tooltip and for copy-to-clipboard. Never re-derive a number in the UI that
the backend already computed: two roundings disagree eventually, and the screen loses.

## Missing is not empty, and neither is zero

Three different states, three treatments, no exceptions:

| State | Means | Treatment |
|---|---|---|
| **Zero** | the value is known and it is 0 | the numeral `0`, normal text colour |
| **Missing** | this row should have a value, we don't have it | `—` in `--value-missing`, with a title attribute saying why |
| **Empty** | there are no rows at all | one sentence saying what would appear here, and what to do |

Collapsing missing into zero is the single most damaging thing a data UI can do: it turns
"we don't know" into a confident claim. If the backend cannot distinguish them, fix the
backend before the screen.

## Status

Every status uses a token pair (`--status-*-fg` / `--status-*-bg`), never a bare colour.

| Do | Don't |
|---|---|
| Give each status a **word**, not just a colour chip | Ship a legend the reader must memorise |
| Say what happened, then what to do about it | "Error" with no next step |
| Keep blocked visually distinct from held — they are different outcomes | Treat every non-success as one red state |

## Density

Pick **one** row height per surface (`--row-compact` or `--row-comfortable`) and stay with
it. Mixing densities in one view reads as a bug, not as hierarchy. Use space, weight, and
the type scale for hierarchy instead.

Dense is the default here: this preset assumes a reader comparing many values at once, not
a marketing page. If you are building something else, that is a reason to change the
preset, not to mix.

## Motion and elevation

Neither is in the token set yet, deliberately: nothing in the reference page needs them,
and a token nobody references is a maintenance cost with no reader. Add them when a real
screen needs them, as roles (`--elevation-popover`), not as a scale nobody asks for.

## What the lint covers, so you know what it doesn't

`checks/token-lint.sh --help` prints the exact scope. In short: it requires token
references in colour and typography declarations, in the CSS files you point it at. It
does not see inline styles, CSS-in-JS, SVG presentation attributes, or anything about
layout, spacing rhythm, contrast ratios, or whether the result is any good. Those stay
human judgement — which is why this file is short and the checks are narrow.
