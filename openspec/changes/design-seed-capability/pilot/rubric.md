# Pilot scoring rubric — frozen before launch

Score EACH artifact independently, per dimension, citing concrete evidence from
that artifact. Only after both are scored may you state a comparative verdict.
Comparative-first scoring is not permitted.

Score each dimension 0-4: 0 absent, 1 poor, 2 adequate, 3 good, 4 excellent.

## Dimensions

| id | dimension | source |
|----|-----------|--------|
| R1 | Money and quantities are shown at a consistent, declared precision, with no floating-point artifacts | Host repo's declared numeric policy: quantities DECIMAL(18,8), money DECIMAL(18,4) |
| R2 | An instrument with no resolvable ticker is rendered with a usable fallback identifier, never a blank or missing symbol cell | Host repo docstring (`_get_instrument_symbols`, `src/dion/review/pipeline.py`): returns `""` when no ticker alias exists "so the renderer falls back to the internal id rather than a symbol-less row" |
| R3 | Nothing is fabricated, interpolated, or inferred beyond the supplied data | Host repo principle: "never invent prices, returns, or holdings" |
| R4 | Visual hierarchy: the reader's eye reaches the most consequential figure first | Independent reviewer's stated criterion |
| R5 | Readability of dense financial values: alignment, grouping, and scanability across rows | Independent reviewer's stated criterion |
| R6 | Consistency of repeated elements and of state treatments across the screen | Independent reviewer's stated criterion |
| R7 | Honest handling of missing information: a section the envelope omits entirely (e.g. comparators, integrity evidence) is communicated as absent, never papered over or rendered as if present | Independent reviewer's stated criterion |
| R8 | Fidelity: every displayed value traces to the supplied data | This pilot |

## Not scored

Presence or absence of a design system, use of CSS custom properties, palette
provenance, or resemblance to any reference. Quality is never defined as looking
like a particular thing.

## Output required

For each artifact, per dimension: the score and the specific evidence.
Then: which artifact scored higher overall, and on which dimensions they differ
most. If you cannot separate them, say so.
