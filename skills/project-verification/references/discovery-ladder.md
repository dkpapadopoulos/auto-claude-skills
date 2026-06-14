# Discovery Ladder

First-match-wins, top-down. Record the rung that fired as `discovery_source`.

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
```
`discovery_source: verify-yml`.

## 2. Manifest-standard targets

Read what is actually declared (never assume a command exists):
- `package.json` → `scripts.test`, `scripts.lint`, `scripts.typecheck` (only those present).
- `Makefile` → `test`, `lint`, `check`, `verify`, `ci` targets (only those present).
- `pyproject.toml` → `pytest` (prefer `uv run pytest` if `uv.lock` exists), `ruff check .` if ruff declared, `pyright`/`mypy` if declared.
- `go.mod` → `go test ./...`, `go vet ./...`.
- `Cargo.toml` → `cargo test`, `cargo clippy`.

`discovery_source: heuristic:<manifest>`.

## 3. `CLAUDE.md` `## Commands` table (bounded classifier)

Parse the markdown table. Apply this classifier:
- INCLUDE a row whose Description contains, case-insensitively, at least one of these substrings: `run all`, `test suite`, `all tests` (so a description like "Run all test suites" qualifies). The row's Command must contain no `<placeholder>`.
- EXCLUDE syntax checks (`-n`), env-prefixed debug invocations (e.g. `SKILL_EXPLAIN=1 …`, `FOO=1 …`), single-file lints, and any command containing a `<placeholder>`.

If exactly one row survives → use it (`discovery_source: claude-md-commands`).
If 0 or ≥2 survive → STOP, present the candidate commands, prompt the user to choose which is the gate, and offer to write `.verify.yml`. Never guess silently.

## 4. No gate found

Emit `discovered: false`, ask the user to add `.verify.yml`, do not guess.

## Honest contract

Zero-config best-effort; `.verify.yml` is the supported correctness contract. Manifest-free repos whose only gate lives in a mixed `## Commands` table (e.g. this one) require either rung-3 disambiguation or a `.verify.yml`.
