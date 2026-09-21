# Dion — Investment Operating System

## Project Overview

Read-only investment operating system for a long-horizon IBKR private investor.
Python computes all data deterministically; Codex orchestrates, explains, and consumes structured outputs only.

## Tech Stack

- **Runtime:** Python 3.12, uv, ruff, pytest, pyright (strict)
- **Database:** DuckDB (canonical analytics store)
- **CLI:** Typer (`dion flex validate|load|inspect`, `dion market sync`, `dion review`, `dion propose`, `dion report`)
- **Validation:** Pandera (two-layer) + post-load SQL assertions
- **Optimizer:** skfolio (primary, Mean-CVaR + CDaR + Michaud resampling), riskfolio-lib (shadow)
- **Market Data:** OpenBB (daily prices, cached in DuckDB)

## Key Principles

1. **Rules first, Codex second.** Never invent prices, returns, or holdings.
2. **Flex is the first truth source.** IBKR Activity Flex XML is authoritative.
3. **Fail closed on structure, fail open on data.** Missing required elements abort. Unknown fields are preserved.
4. **Immutability by default.** Raw XML and artifacts stored in DuckDB + filesystem with content hashes.

## Commands

```bash
# Spec 1: Flex ingestion
dion flex validate <xml>           # Parse and validate without loading
dion flex load <xml> [<xml>...]    # Full pipeline: parse → validate → load → artifact
dion flex inspect <run-id>         # Query loaded data

# Spec 2: Daily operating loop
dion market sync                   # Fetch daily prices for universe instruments
dion universe bootstrap            # Pre-funding: seed instruments from committed reference
dion reconcile preflight           # Pre-solver gate: statement vs computed state
dion review                        # Full review: eligibility → optimize → propose → report
dion propose                       # Generate rebalancing proposal
dion report <identifier>           # Retrieve stored review report
```

All commands output JSON by default. Use `--pretty` for human-friendly JSON, `--format text` for plain text.

`review` and `propose` run the preflight reconciliation gate before the solver
and exit 1 if it blocks. Before an IBKR account exists, `--pre-funding` waives the
statement-derived checks (keeping manifest verification live) — an assertion the gate
refuses structurally the moment any Flex ingest exists. See
`docs/runbooks/pre-funding-cold-start.md`. A discrepancy is cleared by fixing the data, or
deliberately acknowledged with `--ack-breach <check-id>`; each ack is bound to
the exact statement, evidence and diff it was taken against, so it does not
carry forward to a later or larger discrepancy.

## Project Layout

- `src/dion/` — Main package
- `src/dion/ingest/` — Flex XML parser + normalizer + loader
- `src/dion/data/` — DuckDB schema + queries
- `src/dion/validation/` — Pandera models + post-load assertions
- `src/dion/artifacts/` — Run artifact builder + dual storage
- `src/dion/config/` — Policy config models + TOML loader
- `src/dion/market/` — Market data fetcher + return computation
- `src/dion/eligibility/` — Account-profile-based instrument filtering
- `src/dion/optimizer/` — Backend-agnostic contract, skfolio + riskfolio backends, chooser. `dro_ep_wrap` is research-shelf only (closed 2026-05-20; see header of `src/dion/optimizer/dro_prior.py`).
- `src/dion/proposal/` — Position classification, order sizing, report builder
- `src/dion/review/` — Full review pipeline orchestration
- `config/` — Repo-versioned policy TOML (account, universe, optimizer, costs, market data)
- `tests/fixtures/` — Synthetic IBKR Flex XML files
- `data/` — Runtime data (gitignored): raw XML, artifacts, DuckDB

## Numeric Policy

| Category | DuckDB Type |
|----------|-------------|
| Quantities | DECIMAL(18,8) |
| Money amounts | DECIMAL(18,4) |
| Prices / FX rates | DECIMAL(18,8) |

## Testing

```bash
uv run pytest                  # Run all tests
uv run pytest -v               # Verbose
uv run ruff check src/ tests/  # Lint
uv run pyright src/             # Type check
```

### Local CI gate (authoritative pre-merge verification)

GitHub-hosted CI on this private repo is metered (Actions minutes) and unreliable, so the
authoritative gate runs on **local/device resources**:

```bash
bash scripts/ci.sh             # uv sync --frozen + ruff + pyright src/ + pytest -m "not slow"
```

Enable it as an automatic pre-push gate (one-time per clone):

```bash
git config core.hooksPath .githooks   # wires .githooks/pre-push -> scripts/ci.sh
```

A red gate blocks the push. A green `scripts/ci.sh` run from a clean tree records a pass
for that commit in `.git/dion-ci-passed/`. Clean means no tracked changes, no untracked files other
than `.agents/`, `.codex/` and `AGENTS.md`, and no ignored files under the gate's inputs
(`src/ tests/ scripts/ config/`, bar `__pycache__`), at start and end. The
hook then skips the re-run for a recorded commit, and for branch deletions, so `--no-verify`
is not needed for either. Any other push runs the full gate. Bypassing with
`git push --no-verify` is still discouraged. The ~20min `-m slow` lane is advisory — run
`uv run pytest -m slow` separately on pipeline/optimizer/research-heavy changes.

**A test that shells out to git must scrub git's location variables.** Git exports them
to its hooks, and `.githooks/pre-push` runs the whole suite. Measured (git 2.54.0):
`GIT_CONFIG_PARAMETERS`, `GIT_INDEX_FILE` and `GIT_PREFIX` are exported from **any**
checkout; `GIT_DIR` additionally when the checkout is a **linked worktree** (which this
repo's are); `GIT_WORK_TREE` when an explicit `--work-tree` or `core.worktree` is in
play. Do not read this as "only worktrees are affected" — most of the family travels
regardless of checkout shape.

**`git -C <path>` does not override them:** it changes directory, not the repository. A
test that builds a throwaway repo therefore retargets *the repository being pushed* —
`git init` silently reinitialises it (no `.git` appears in the temp dir), `git add .`
stages the deletion of every tracked file it does not contain, and the commit lands on
the branch being pushed. Two such commits (author `t <t@t>`, subject `init`, ~236k
deletions) reached `design-seed-pilot` this way; they are kept as
`rescue/unknown-init-16eedb8` and `rescue/unknown-init-97b2fe9`.

Two layers, because the failure is silent and destructive and prose alone did not hold:

1. `.githooks/pre-push` runs `unset $(git rev-parse --local-env-vars)` before exec'ing
   the gate, so the whole suite is clean whatever any individual test does. Measured:
   with the Python scrub deliberately reverted, this alone leaves the pushed
   repository's HEAD unmoved.
2. Tests pass `env=_clean_env()` to every git subprocess (`tests/test_pre_push_hook.py`),
   which also covers a `bash` child that then runs git. The list is git's own
   `rev-parse --local-env-vars`, asserted to stay a superset by a test, so it cannot fall
   behind a release.

`--no-verify` avoids the corruption only by skipping the gate entirely, so it is not the
remedy for this.

## Validation

Run `docs/runbooks/real-data-validation.md` to validate the full cockpit against real IBKR data.
Stages: flex load → market sync → review → report/propose → optional research.
Rerun after code changes, config changes, new instruments, or dependency upgrades.
