# Discovery Ladder

First-match-wins, top-down. The rung that fires decides WHICH commands are the
gate.

**Whether the rung's NAME survives into `discovery_source` depends on who writes
the artifact.** The deterministic writer owns that field and records only two
values: `verify-yml` when the gate came from a declared `.verify.yml` (§1), and
`explicit` when the caller supplied it (`--name/--run`, the no-`.verify.yml` path
in SKILL.md) — so §1's name does survive, while §2 and §3 collapse to `explicit`
and are not recoverable from the record. The writer owns the field precisely so
a caller-supplied gate cannot claim to be a declared one. The §2 and §3 names
below therefore appear only on the hand-authored last resort.

## 1. `.verify.yml` (authoritative — the correctness contract)

If present and parseable, use it verbatim and STOP. Schema (flat, parallels `.deploy-checklist.yml`):

```yaml
substrate: local          # v1: MUST be "local"; any other value is an error
commands:
  - name: lint
    run: ruff check .
  - name: types
    run: pyright
  - name: tests
    run: uv run pytest -m "not slow"
fail_fast: false          # run all and aggregate; default false
gate_gaming_paths:        # optional: the paths the gate-gaming check reads
  - tests/
```

`gate_gaming_paths` is optional. Without it the check reads every path whose
name contains `test` or `spec`. With it, the check reads exactly these paths
plus `.verify.yml`. Rules, all enforced by `scripts/verify-and-record.sh`:

- It is read from the **merge-base with the mainline**, not from the branch or
  the working tree. Adding or changing it on a branch does not change the scope
  that branch is judged by.
- A branch whose committed declaration differs from the merge-base's cannot read
  `clean` (a clean result becomes `suspect`), unless every path declared at the
  merge-base is still declared. Adding a first declaration, removing one, and
  making one unusable all count.
- A top-level block list of plain, unquoted, repository-relative paths or globs
  (`tests/`, `tests/test_*.py`). Refused: an inline `[a, b]` list, quotes, a
  leading `:` (pathspec magic such as `:(exclude)`), a leading `-` or `/`, `..`,
  and whitespace inside an entry. Only this key is parsed; the rest of the file
  is not validated.
- Every entry must match at least one file at the merge-base.
- If the declaration at the merge-base breaks any of those rules the check does
  not run: `gate_gaming_status` is `unverified` and the writer prints the reason.
  It never applies part of a list and never falls back to the name glob.
- A `.verify.yml` that is a symlink at the merge-base declares nothing.
- List every path the gate runs. A test file that hands its assertions to a
  script elsewhere needs that script listed too. Nothing verifies the list is
  complete.
`discovery_source: verify-yml` — recorded by the deterministic writer on this
rung, and the one rung name that survives into the artifact.

## 2. Manifest-standard targets

Read what is actually declared (never assume a command exists):
- `package.json` → `scripts.test`, `scripts.lint`, `scripts.typecheck` (only those present).
- `Makefile` → `test`, `lint`, `check`, `verify`, `ci` targets (only those present).
- `pyproject.toml` → `pytest` (prefer `uv run pytest` if `uv.lock` exists), `ruff check .` if ruff declared, `pyright`/`mypy` if declared.
- `go.mod` → `go test ./...`, `go vet ./...`.
- `Cargo.toml` → `cargo test`, `cargo clippy`.

`discovery_source: heuristic:<manifest>` — hand-authored verdicts only; via the
deterministic writer this is recorded as `explicit`.

## 3. `CLAUDE.md` `## Commands` table (bounded classifier)

Parse the markdown table. Apply this classifier:
- INCLUDE a row whose Description contains, case-insensitively, at least one of these substrings: `run all`, `test suite`, `all tests` (so a description like "Run all test suites" qualifies). The row's Command must contain no `<placeholder>`.
- EXCLUDE syntax checks (`-n`), env-prefixed debug invocations (e.g. `SKILL_EXPLAIN=1 …`, `FOO=1 …`), single-file lints, and any command containing a `<placeholder>`.

If exactly one row survives → use it (hand-authored `discovery_source:
claude-md-commands`; via the deterministic writer, `explicit`).
If 0 or ≥2 survive → STOP, present the candidate commands, prompt the user to choose which is the gate, and offer to write `.verify.yml`. Never guess silently.

## 4. No gate found

Emit `discovered: false`, ask the user to add `.verify.yml`, do not guess.

## Honest contract

Zero-config best-effort; `.verify.yml` is the supported correctness contract. Manifest-free repos whose only gate lives in a mixed `## Commands` table (e.g. this one) require either rung-3 disambiguation or a `.verify.yml`.
