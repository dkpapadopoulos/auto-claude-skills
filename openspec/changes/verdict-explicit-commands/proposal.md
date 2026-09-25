# Let the deterministic writer record a gate it did not discover

## Why

`scripts/verify-and-record.sh` does two separable jobs — decide **which** commands
are the gate, and **run them while recording what happened** — and refuses both
together whenever `.verify.yml` is absent (`"refusing to guess the gate"`). So
every repo without one falls through to `project-verification/SKILL.md` Step 3,
which instructs the **model** to hand-author the verdict JSON.

A hand-authored verdict records what the model believed. A written one records
measured exit codes. Nothing downstream can tell them apart: `verdict_is_clean`
reads only `failed`, `could_not_verify` and `gate_gaming_status`, and ignores the
`writer` field the honest path already stamps.

Local corpus: **41 verdicts, 37 stamped `writer: verify-and-record.sh`, 4 with no
writer at all** — and the field spans the whole window, so absence is not age.

This matters now because of **#301**: invoking `verification-before-completion`
and executing nothing already satisfies the VERIFY gate, since the Skill return
is the instruction body. A measured verdict is the **only** evidence in this
system that proves commands ran, so reducing hand-authored verdicts is the
prerequisite to ever requiring one.

## What Changes

**Explicit-commands mode.** `--name X --run "CMD"`, repeatable. The caller says
which commands constitute the gate — after the discovery ladder's own
disambiguation, which may involve the user — and the script executes them and
records its own exit codes, stamping `discovery_source: explicit`.

Three refusals. Each of the *enforcement* guards is pinned by a
mutation-verified test; R2 is structural — there is no flag to override, so what
is pinned is that an override attempt is rejected as an unknown argument:

1. **A declared gate wins.** Explicit args are refused when `.verify.yml` exists;
   the declaration is the repo's contract and must not be substituted by a
   narrower set.
2. **Provenance is script-owned.** There is no `--discovery-source` flag. A
   caller-supplied rung would let explicit mode impersonate `verify-yml` and
   imply a declaration that does not exist.
3. **Refuse, never silently transform.** The pair transport is `\x1f`-delimited
   and read line-wise, and names are comma-split at serialization, so a multiline
   command or a comma in a name is rejected rather than corrupted into a shape
   the reader cannot detect. A dangling `--name` with no `--run` is rejected too:
   it would drop a declared check, under-gating toward a false clean.

`project-verification/SKILL.md` is updated to use it, so hand-authoring becomes
the last resort only (no `jq`, or the script cannot run).

### Deliberately NOT included: manifest auto-detection

The discovery ladder's rung 2 (`package.json` scripts, `Makefile` targets, …) is
**not** implemented. **A declared tool is not a declared gate.** It fails in both
directions: a root `"test": "echo ok"` manufactures a clean verdict, while
selecting every recognisable target promotes optional, environment-dependent
checks into mandatory gates whose failures become denials — and multi-manifest
precedence is unspecified. Deterministic selection can still select the wrong
gate. Selection stays with the caller; only measurement moves.

## Capabilities

- **MODIFIED** `pdlc-safety` — how a verification verdict may be produced.

## Impact

- `scripts/verify-and-record.sh` — argument parsing and a second PAIRS source.
  The execution loop, token lifecycle (#122/#156), pre-gate sha capture and
  straddle detection (#181), `could_not_verify` semantics and the subshell /
  `set +u` / nulled-stdin contract are all unchanged and shared.
- `skills/project-verification/SKILL.md` — the no-`.verify.yml` path.
- `tests/test-verify-and-record.sh` — 11 cells, 4 mutation-verified guards.

## A claim this change does NOT make

**It does not leave gate decisions unchanged.** No enforcement code moves and no
predicate changes, but the population of verdicts that *exist* does, and three
legs consume `verdict_is_clean`. Newly reachable outcomes, assuming other legs
are satisfied:

| Previously | Now |
|---|---|
| No VERIFY evidence, no blocking chain leg | global VERIFY passes |
| Routing changes, no covering verdict | routing-governance passes |
| VERIFY milestone complete, no failing verdict | verify-hardening can newly **deny** |
| A clean covering verdict exists | a later run replaces it with a failure |

It is bidirectional, and "predicate identity" is not an exemption from saying so.
What bounds it is that explicit mode does not *create* verdicts where none was
intended — the model was already about to author one — it changes their
provenance. That bound is an **assumption about the intended workflow, not an
enforced property**: nothing stops a caller invoking the writer in a repo where
no verdict would otherwise have been produced. That is why manifest auto-detection, which genuinely would grow the
population, is excluded above.

The active-chain VERIFY leg still does **not** accept a verdict (#254), unchanged.
