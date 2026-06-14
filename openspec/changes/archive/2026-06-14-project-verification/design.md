# Design: Project-Native Verification Primitive

## Architecture

### The load-bearing split: skill reasons, hook cannot

A **model-invoked skill** can read freeform prose, disambiguate, and ask the user. A **hook** can do none of those, cannot invoke an LLM, cannot access the secrets/DB/network a test suite needs, and (per the repo's hard invariant) must fail-open. This split dictates every decision:

- **Discovery + run + evidence** → live in the `project-verification` **skill** (slow, reasoning-heavy, on-demand). Never in the activation/session-start path (budget) or in a hook (can't reason).
- **Hard enforcement** → the only signal a gate can trust is **external** (CI conclusion via `gh`), because anything the gated agent writes (a marker, a freshness cache) it can forge. So the real fail-closed boundary is the `deploy-gate` CI check, not a new marker hook.

### Component map

| Concern | Where | File |
|---|---|---|
| Discover declared gate, run locally, emit evidence | new skill | `skills/project-verification/SKILL.md` |
| Discovery ladder + `.verify.yml` schema | skill ref | `skills/project-verification/references/discovery-ladder.md` |
| Routing entry (REVIEW, role domain) | config | `config/default-triggers.json` + `config/fallback-registry.json` |
| `frontend-playwright` anchoring (Gap 4) | config | both trigger files |
| `deploy-gate` fail-closed CI + accept local evidence (Gap 2) | skill | `skills/deploy-gate/SKILL.md` |
| Tests | tests | `tests/test-project-verification.sh`, `tests/test-routing.sh` |
| Behavioral pack | evals | `tests/fixtures/project-verification/evals/behavioral.json` |

One new skill, edits to files that already own each concern. No new hook file, no new state-token scheme.

### Discovery ladder (deterministic-FIRST, LLM only on a tie)

Codex's correction: do not lead with LLM disambiguation — `CLAUDE.md:9` ("Run all test suites" → `bash tests/run-tests.sh`) is deterministically resolvable here. First-match-wins; the skill records which rung fired as `discovery_source`:

1. **`.verify.yml`** present → authoritative, zero ambiguity. **Stop.** (The correctness path; this repo ships one.)
2. **Manifest-standard targets** — `package.json` `scripts.{test,lint,typecheck}`, `Makefile` `test|lint|check` targets, `pyproject.toml` (`pytest`, `ruff`, `pyright`/`mypy` if declared), `go.mod` (`go test ./...`), `Cargo.toml` (`cargo test`). Read what's declared; never assume.
3. **`CLAUDE.md` `## Commands` table** — parse the table; apply a bounded deterministic classifier: INCLUDE a row whose description matches `/run all|test suite|all tests/i` and whose command has no placeholder (`<name>` ⇒ template, exclude); EXCLUDE syntax checks (`-n`), env-prefixed debug invocations (`FOO=1 …`), single-file lints. If exactly one survives → use it. If 0 or ≥2 survive → **prompt the user** with the candidate list and **offer to write `.verify.yml`** so rung 1 wins next time.
4. **No gate found** → emit `discovered:false`, ask the user, do not guess.

Honest framing in the SKILL.md: **zero-config best-effort; `.verify.yml` is the supported correctness contract.**

### `.verify.yml` schema (parallels the existing `.deploy-checklist.yml`)

```yaml
substrate: local          # v1: MUST be "local"; writer errors otherwise (enum deferred)
commands:
  - name: lint
    run: ruff check .
  - name: types
    run: pyright
  - name: tests
    run: uv run pytest -m "not slow"
fail_fast: false          # run all and aggregate; default false
```

### Evidence artifact

Session-token-scoped, reusing the `~/.claude/.skill-*-<token>` namespace (matches `runtime-validation`'s `.skill-validation-ran-<token>` at `SKILL.md:266`, resolved by the hook at `skill-activation-hook.sh:1350`).

- **Path:** `~/.claude/.skill-project-verified-<token>`
- **Shape:**
```json
{
  "substrate": "local",
  "discovery_source": "claude-md-commands",
  "passed": ["lint", "tests"],
  "failed": ["types"],
  "command": "ruff check . && pyright && uv run pytest -m \"not slow\"",
  "output_excerpt": "pyright: 2 errors in core/engine.py …(truncated ~4000c)",
  "ts": "2026-06-13T09:00:00Z"
}
```
`passed`/`failed` are command *names*; `output_excerpt` is the last ~4 KB of the failing command (single-line-safe, heeding the `\x1f`/newline field discipline). **This file is advisory evidence, not a trust boundary** — it is forgeable and may race across concurrent sessions.

### `frontend-playwright` anchoring (Gap 4)

The trigger is on the **hint path** (`skill-activation-hook.sh:1270`, raw `[[ =~ ]]`), bypassing the scorer's word-boundary post-filter (lines 195-228). So it must self-anchor. `\b` is unusable under Bash 3.2 (`[[ "a ui change" =~ \b(ui)\b ]]` → exit 1, verified; same class as the documented `\d`/`(?:)` trap). Use bracket-class anchors:

```
(^|[^a-z])(component|page|form|modal|dialog|sidebar|navbar|header|footer|button|dropdown|tooltip|tab|card|widget|dashboard|landing.?page|login.?page|signup|onboard|checkout|ui|frontend|layout|style|css|tailwind|responsive)([^a-z]|$)
```

Verified under `/bin/bash 3.2.57`: matches `navbar`, `the button component`, `responsive`, `a ui change`; rejects `tabulate`, `onboarding`, `configure`, `paginate results`. Residual `card the deck`-style misfires are rare and acceptable; drop bare `card`/`tab` if zero-false-positive is required. Both `config/default-triggers.json` and `config/fallback-registry.json` updated (canonical-source rule); regression fixtures added to `tests/test-routing.sh` and run under `/bin/bash`.

### `deploy-gate` fail-closed (Gap 2)

Replace check #1 so empty CI evidence is a FAIL, not a pass:

```bash
_concl="$(gh pr checks --fail-fast 2>/dev/null && echo PASS \
          || gh run list --limit 1 --json conclusion -q '.[0].conclusion')"
[ -z "$_concl" ] && { echo "GATE FAIL: no CI checks reported — absent ≠ green"; exit 1; }
```

Also surface the three states distinctly (green / red / **absent-or-broken**), and accept a fresh local `~/.claude/.skill-project-verified-<token>` with no failures as the verification of record when CI is absent. This keys on an **external** signal — the one boundary the model can't forge.

## Trade-offs

- **Accepting:** discovery is best-effort without `.verify.yml`; the evidence marker is advisory not enforced; substrate is a constant `"local"`. These are deliberate scope cuts, each with a revival trigger.
- **Rejecting:** a model-written freshness/marker gate as hard enforcement (forgeable + races — confirmed); a project-profile subsystem (a once-computed `has_frontend` goes stale with no error signal; the one-line regex fix strictly dominates).

## Dissenting views

- **Critic:** even the v1 skill is "a convenience, not an enforcer"; the genuinely high-value, low-risk pieces are Gap 2 + Gap 4, and they should ship regardless of the skill. (Honored by sequencing them first.)
- **Architect (conceded):** his Round-1 evidence-freshness push-gate was withdrawn as forgeable; chain-completion gating at best answers "was the skill reached," never "did tests pass."
- **Codex:** the CLAUDE.md table is less ambiguous than the in-house debate implied — use a deterministic preference before any LLM fallback; surfaced the opt-in `.git/hooks/pre-push` fourth enforcement option.

## Decisions & Trade-offs (rejected alternatives)

- **Extend `deploy-gate` instead of a new skill** — rejected. `deploy-gate` is `phase: SHIP` (`SKILL.md:5`); verification is `phase: REVIEW` and *produces* the evidence `deploy-gate` *consumes*. A producer cannot live downstream of its consumer.
- **Reuse `runtime-validation`** — rejected. It is realistic-behavior E2E (browser/API/CLI), not declared test/lint/type gate discovery. Blurring semantics fails the "one well-scoped primitive" constraint.
- **Substrate enum {self-hosted, hosted-ci} in v1** — deferred. Repo has only GitHub-hosted CI, zero self-hosted runners. Revival: a named adopter with a self-hosted runner who states the pain. v1 writes the literal `"local"` and errors on any other value.
- **Project-profile subsystem** — rejected (not merely deferred). Stale-state-with-no-error-signal failure class; the regex fix delivers the named acceptance criterion at near-zero cost.
- **In-hook test execution / model-written marker as hard gate** — rejected. Latency + fail-open contract + forgeability. External CI signal is the only trustable hard boundary.

## Out-of-scope

- **Gap 3 phase-reconciliation** (check branch/diff/PR before asserting IMPLEMENT/REVIEW/SHIP) — a composition-state-machine change touching the walker in `skill-activation-hook.sh` and `openspec-guard.sh`. Orthogonal; its own issue/debate. Revival: the tracker asserts REVIEW/SHIP with no branch/diff/PR in ≥1 more real session after this ships.
- v2 `openspec-guard` marker-read (skip-friction) and the opt-in `.git/hooks/pre-push` installer — designed here, built in a fast-follow once the v1 marker is observed in a real session.

## Implementation Notes (synced at ship time)

Built as designed; all three capabilities' acceptance scenarios implemented, full suite 59/59 green. Deviations and discoveries during implementation:

- **`frontend-playwright` lives under `methodology_hints[]`, not `skills[]`.** The plan assumed it was a `skills[]` routing entry. It is a methodology hint on the raw hint path (`hooks/skill-activation-hook.sh:1270`), which is *not* covered by the scorer's word-boundary post-filter (lines 195-228) — so the anchoring had to live in the regex itself (confirming the design's bracket-class-not-`\b` decision). The zero-LLM fixture harness `tests/test-regex-fixtures.sh` was extended (additively) to also resolve triggers from `methodology_hints[]`, else the fixture would have been inert.
- **`deploy-gate` CI snippet hardened twice in review.** `gh pr checks` stdout is now silenced (`>/dev/null 2>&1`) so `$_concl` is literally `PASS` on green; and a prose guard was added so a red `gh pr checks` is not masked by a stale `gh run list` success.
- **Behavioral pack path** is `tests/fixtures/project-verification/evals/behavioral.json` (the repo's `tests/fixtures/<cap>/evals/` convention), not the `tests/fixtures/evals/<cap>.behavioral.json` path named in early drafts of this doc (since corrected). `scenario-coverage.sh` will track it once this spec is archived to `openspec/specs/`.
- **Gap 3 (phase-reconciliation) stayed out of scope** as designed — and was vividly motivated *during this very session*, where the composition tracker repeatedly asserted DEBUG/DISCOVER/REVIEW phases while implementation was mid-flight. Recorded as the revival trigger.
- **Substrate enum** correctly deferred: v1 errors on any `.verify.yml` `substrate` ≠ `local`; the enum is unbuilt.
