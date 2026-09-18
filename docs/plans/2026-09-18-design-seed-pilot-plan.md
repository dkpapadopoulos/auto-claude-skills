# Design-Seed Two-Arm Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the instrument and the subject fixtures for a pre-registered two-arm comparison, run both arms, and adjudicate the result under rules fixed before launch.

**Architecture:** Two repos with a hard split — **Dion holds the subject** (frozen fixture, task brief, the arms' worktrees), **auto-claude-skills holds the instrument** (rubric, advance disclosures, budget rules, egress check, capture harness, adjudication). The arms are fresh subagents in disposable `git worktree`s with no egress capability; the orchestrator has egress but sends only human-approved frozen packages that pass a mechanical hash check.

**Tech Stack:** Bash 3.2 + jq (plugin instrument), Python 3.12 + pytest (Dion fixtures), headless Chromium via `npx playwright` (instrument-side capture only), `scripts/consult-dispatch.sh` (judging egress).

**Spec:** `openspec/changes/design-seed-capability/design.md` § "Pilot pre-registration — 2026-09-18", and `openspec/changes/design-seed-capability/specs/design-foundations/spec.md`.

## Global Constraints

- Bash 3.2 compatible (macOS `/bin/bash`). No associative arrays. Never quoted operands in `$(( ))`.
- Every plugin test file is `tests/test-*.sh`, discovered by `tests/run-tests.sh`.
- **No Node/Vite toolchain is added to Dion.** `npx playwright` runs instrument-side only.
- **Nothing in this pilot may default into `data/`.** Every `dion` invocation passes an explicit `--db-path` to a throwaway path.
- **Tasks 1-7 must ALL be complete and committed before Task 8 runs.** Launching an arm with any pre-launch artifact missing voids the pre-registration.
- **Arms are bounded by a deny hook, not by their tool list.** `general-purpose` has tool access `*` and the Agent tool takes no tool-restriction parameter, so "arms have no egress tools" was never true. `.claude/hooks/pilot-arm-deny.py` refuses the named outbound tools and the enumerated sensitive paths; Bash-level network egress is residual and named. See Task 8 Step 4.
- The data-embedding contract, mandated by the brief and relied on by the egress check: exactly one `<script type="application/json" id="dion-report">` block containing the **complete envelope verbatim**.
- Any protocol change made after results are seen makes this **v2**; v1 results are not pooled.

## Verification criteria carried from the spec

Each maps to the task that satisfies it:

| Spec scenario | Task |
|---|---|
| The fixture preserves the gaps the screen is meant to discover | Task 2 |
| The rubric cannot reward looking like the seed | Task 5 |
| An artifact carrying non-fixture data is refused | Task 1 |
| Disagreeing judges yield an inconclusive result, not a tiebreak | Task 12 |
| A single-arm pilot does not license a comparative claim | Task 12 |

## File Structure

**auto-claude-skills (instrument):**
- `scripts/pilot-egress-check.sh` — refuses an artifact whose embedded data is not the fixture. One responsibility: the pre-egress gate.
- `scripts/pilot-capture.sh` — deterministic browser capture. One responsibility: screenshots.
- `openspec/changes/design-seed-capability/pilot/rubric.md` — scored dimensions and their pre-seed sources.
- `openspec/changes/design-seed-capability/pilot/brief.md` — the task brief handed to both arms.
- `openspec/changes/design-seed-capability/pilot/advance-disclosures.md` — what is disclosed before launch.
- `openspec/changes/design-seed-capability/pilot/budget.md` — cap, stopping rule, timeout, retry allowance.
- `openspec/changes/design-seed-capability/pilot/HASHES.md` — recorded sha256 of every frozen artifact.
- `tests/test-pilot-egress-check.sh`, `tests/test-pilot-artifacts.sh`, `tests/test-pilot-capture.sh`

**Dion (subject):**
- `tests/design_seed_pilot/build_fixture.py` — builds the fixture through store-then-retrieve.
- `tests/fixtures/design_seed_pilot/review_report_envelope.json` — the frozen fixture.
- `tests/design_seed_pilot/test_fixture_fidelity.py` — the fixture is real and gap-preserving.
- `tests/design_seed_pilot/test_fixture_adequacy.py` — the fixture exercises every scored state.

---

### Task 1: Pre-egress hash assertion

The safety control the trifecta review required. Authored **failing first** — a check that has never refused anything has never been shown to work. Do this before anything else; nothing may leave the machine until it exists.

**Files:**
- Create: `scripts/pilot-egress-check.sh`
- Test: `tests/test-pilot-egress-check.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/pilot-egress-check.sh <artifact.html> <fixture.json>` — exit 0 when the artifact's embedded data canonicalises identically to the fixture; exit 1 with a reason on stderr otherwise. Used by Task 11 before every judging package.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/test-pilot-egress-check.sh <<'EOF'
#!/bin/bash
# test-pilot-egress-check.sh — the pre-egress gate must refuse contaminated artifacts.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK="${ROOT}/scripts/pilot-egress-check.sh"
PASS=0; FAIL=0
_ok()   { printf '  PASS %s\n' "$1"; PASS=$(( PASS + 1 )); }
_bad()  { printf '  FAIL %s\n' "$1"; FAIL=$(( FAIL + 1 )); }
_assert_exit() { # <expected> <label> <artifact> <fixture>
    "${CHECK}" "$3" "$4" >/dev/null 2>&1
    _got=$?
    if [ "${_got}" = "$1" ]; then _ok "$2"; else _bad "$2 (expected exit $1, got ${_got})"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cat > "${TMP}/fixture.json" <<'JSON'
{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}
JSON

# Clean: same data, keys reordered and whitespace added. MUST pass.
{ printf '<html><body><script type="application/json" id="dion-report">\n'
  printf '{ "data" : { "report" : { "proposal_summary" : { "orders" : [ { "expected_fee_chf" : null, "symbol" : "VWRL" } ] }, "report_id" : "r1" } }, "command" : "report", "ok" : true }\n'
  printf '</script></body></html>\n'; } > "${TMP}/clean.html"

# Contaminated: one extra holding that is not in the fixture. MUST be refused.
{ printf '<html><body><script type="application/json" id="dion-report">\n'
  printf '{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null},{"symbol":"REAL","expected_fee_chf":12.5}]}}}}\n'
  printf '</script></body></html>\n'; } > "${TMP}/dirty.html"

# No data block at all. MUST be refused, never silently allowed.
printf '<html><body><p>no data here</p></body></html>\n' > "${TMP}/noblock.html"

# Two data blocks — ambiguous. MUST be refused.
{ cat "${TMP}/clean.html"; cat "${TMP}/clean.html"; } > "${TMP}/double.html"

# Malformed JSON in the block. MUST be refused.
printf '<html><script type="application/json" id="dion-report">{not json}</script></html>\n' > "${TMP}/bad.html"

echo "test-pilot-egress-check"
_assert_exit 0 "clean artifact (reordered keys) is allowed"      "${TMP}/clean.html"   "${TMP}/fixture.json"
_assert_exit 1 "contaminated artifact is refused"                "${TMP}/dirty.html"   "${TMP}/fixture.json"
_assert_exit 1 "artifact with no data block is refused"          "${TMP}/noblock.html" "${TMP}/fixture.json"
_assert_exit 1 "artifact with two data blocks is refused"        "${TMP}/double.html"  "${TMP}/fixture.json"
_assert_exit 1 "artifact with malformed JSON is refused"         "${TMP}/bad.html"     "${TMP}/fixture.json"
_assert_exit 1 "missing fixture is refused"                      "${TMP}/clean.html"   "${TMP}/nope.json"

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
EOF
chmod +x tests/test-pilot-egress-check.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-pilot-egress-check.sh < /dev/null`
Expected: FAIL — the clean-artifact cell reports `expected exit 0, got 127` because `scripts/pilot-egress-check.sh` does not exist. Confirm the refusal cells are **not** the reason it fails: a missing script exits 127, not 1, so all six cells must be wrong before implementation. If any refusal cell passes here, the test is vacuous — fix it before continuing.

- [ ] **Step 3: Write minimal implementation**

```bash
cat > scripts/pilot-egress-check.sh <<'EOF'
#!/bin/bash
# pilot-egress-check.sh — refuse to transmit an artifact whose embedded data is
# not the frozen pilot fixture.
#
# The trifecta review found the residual risk: an arm reads real portfolio data
# by absolute path and inlines it, and a human preview of a 7 KB HTML file will
# not catch a plausible-looking row. This check is mechanical on purpose — no
# human judgement is involved in the refusal.
#
# Refuses on ANY doubt (missing block, two blocks, malformed JSON, absent
# fixture, no jq). Refusing costs one regeneration; allowing costs a leak.
set -u

_die() { printf 'pilot-egress-check: %s\n' "$*" >&2; exit 1; }

[ $# -eq 2 ] || _die "usage: pilot-egress-check.sh <artifact.html> <fixture.json>"
_ART="$1"; _FIX="$2"

[ -r "${_ART}" ] || _die "artifact unreadable: ${_ART} — refused"
[ -r "${_FIX}" ] || _die "fixture unreadable: ${_FIX} — refused"
command -v jq >/dev/null 2>&1 || _die "jq unavailable — refused rather than skipped"

_N="$(grep -c 'id="dion-report"' "${_ART}" 2>/dev/null)" || _N=0
[ "${_N}" = "1" ] || _die "expected exactly one data block, found ${_N} — refused"

_EMB="$(awk '/<script[^>]*id="dion-report"/{f=1;next} f&&/<\/script>/{exit} f' "${_ART}")"
[ -n "${_EMB}" ] || _die "data block is empty — refused"

_A="$(printf '%s' "${_EMB}" | jq -S -c . 2>/dev/null)" \
    || _die "embedded block is not valid JSON — refused"
_B="$(jq -S -c . "${_FIX}" 2>/dev/null)" \
    || _die "fixture is not valid JSON — refused"

[ "${_A}" = "${_B}" ] \
    || _die "embedded data differs from the frozen fixture — refused"

printf 'ok: embedded data matches the frozen fixture\n'
EOF
chmod +x scripts/pilot-egress-check.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-pilot-egress-check.sh < /dev/null`
Expected: PASS — `6 passed, 0 failed`.

- [ ] **Step 5: Mutation-verify the check is load-bearing**

Run:
```bash
cp scripts/pilot-egress-check.sh /tmp/pilot-egress-check.bak
perl -0pi -e 's/\Q[ "\${_A}" = "\${_B}" ]\E/[ 1 = 1 ]/' scripts/pilot-egress-check.sh
bash tests/test-pilot-egress-check.sh < /dev/null; echo "mutated exit=$?"
cp /tmp/pilot-egress-check.bak scripts/pilot-egress-check.sh
bash tests/test-pilot-egress-check.sh < /dev/null; echo "restored exit=$?"
```
Expected: mutated exit=1 with the contaminated-artifact cell failing; restored exit=0. If the mutation leaves the suite green, the test asserts nothing — fix it before continuing.

- [ ] **Step 6: Commit**

```bash
git add scripts/pilot-egress-check.sh tests/test-pilot-egress-check.sh
git commit -m "feat: mechanical pre-egress check for pilot artifacts"
```

---

### Task 2: Frozen fixture through store-then-retrieve

The one shortcut that silently destroys the experiment is building this by calling `build_review_report()` directly — `comparators` and `integrity_evidence` are live on the in-memory dataclass and only go missing across persistence.

The repo already has the machinery: `tests/review/_db_fixtures.py::_setup_full_db(con)` seeds a full synthetic DB, and `run_review(...)` runs the pipeline and INSERTs into `review_reports` (`src/dion/review/pipeline.py:2204`). Use an **in-memory** connection: it goes through the same `report_json` column — which is where the fields are lost — while making the private store unreachable by construction rather than by passing the right flag.

**Files (Dion repo):**
- Create: `tests/design_seed_pilot/__init__.py` (empty)
- Create: `tests/design_seed_pilot/build_fixture.py`
- Create: `tests/fixtures/design_seed_pilot/review_report_envelope.json`
- Test: `tests/design_seed_pilot/test_fixture_fidelity.py`

**Interfaces:**
- Consumes: `tests.review._db_fixtures._setup_full_db`, `dion.review.pipeline.run_review`, `dion.config.loader.load_config`, `dion.data.schema.create_schema`.
- Produces: `build_fixture() -> dict[str, Any]` (no arguments — see below) and `VOLATILE_REPORT_KEYS: frozenset[str]`. Tasks 3, 6, 8 and 9 read the committed JSON.

- [ ] **Step 1: Write the failing test**

```python
# tests/design_seed_pilot/test_fixture_fidelity.py
"""The pilot fixture must be a REAL retrieved envelope, not a constructed one."""
from __future__ import annotations

import json
from pathlib import Path

from tests.design_seed_pilot.build_fixture import VOLATILE_REPORT_KEYS, build_fixture

FIXTURE = Path("tests/fixtures/design_seed_pilot/review_report_envelope.json")
SOURCE = Path("tests/design_seed_pilot/build_fixture.py")


def _stable(report: dict) -> dict:
    """Drop per-run identifiers so two runs are comparable."""
    return {k: v for k, v in report.items() if k not in VOLATILE_REPORT_KEYS}


def test_fixture_is_committed() -> None:
    assert FIXTURE.exists(), "frozen fixture is missing"


def test_fixture_matches_a_fresh_store_retrieve() -> None:
    """Regenerating through persistence reproduces the committed content.

    Compared with volatile keys removed: report_id, review_run_id, created_at
    and content_hash differ on every run by design, and comparing them would
    make this test fail for a reason unrelated to what it checks.
    """
    fresh = build_fixture()
    committed = json.loads(FIXTURE.read_text())
    assert _stable(fresh["data"]["report"]) == _stable(committed["data"]["report"])


def test_persistence_dropped_fields_are_absent() -> None:
    """comparators and integrity_evidence are live in memory and lost on store.

    If these are present, the fixture was built by calling the report builder
    directly. That erases two of the four known gaps and makes the
    contract-delta criterion unfalsifiable.
    """
    report = json.loads(FIXTURE.read_text())["data"]["report"]
    assert report.get("comparators") in (None, {}), (
        "comparators survived — fixture was not produced through persistence"
    )
    assert not report.get("integrity_evidence"), (
        "integrity_evidence survived — fixture was not produced through persistence"
    )


def test_fixture_can_never_reach_the_private_store() -> None:
    """The builder must use an in-memory database and name no real path.

    `dion report --db-path` defaults to data/dion.duckdb. The pilot is never one
    omitted argument away from the private store: there is no path argument.
    """
    src = SOURCE.read_text()
    assert 'duckdb.connect(":memory:")' in src, "must use an in-memory connection"
    assert "data/dion.duckdb" not in src, "must never name the private store"
    assert "data/" not in src.replace("tests/data", ""), "must not reference data/"


def test_envelope_shape_matches_the_cli() -> None:
    """The arms consume the envelope, not a bare report."""
    env = json.loads(FIXTURE.read_text())
    assert env["ok"] is True
    assert env["command"] == "report"
    assert "report" in env["data"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/damian/IdeaProjects/Dion && uv run pytest tests/design_seed_pilot/test_fixture_fidelity.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tests.design_seed_pilot.build_fixture'`.

- [ ] **Step 3: Write minimal implementation**

```python
# tests/design_seed_pilot/build_fixture.py
"""Produce the pilot fixture through the STORE-THEN-RETRIEVE path.

Deliberately does NOT call build_review_report() and serialise its result.
`dion report` reads a stored `report_json` column (src/dion/cli.py:963); two
fields on the in-memory dataclass — comparators and integrity_evidence — only
go missing across that boundary. A fixture that skips persistence carries them,
which erases two of the four data gaps the pilot screen is meant to discover.

The connection is in-memory and takes no path argument, so the real
data/dion.duckdb is unreachable from here by construction rather than by
remembering a flag.
"""
from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from typing import Any

import duckdb

from dion.config.loader import load_config
from dion.review.pipeline import run_review
from tests.review._db_fixtures import _setup_full_db

#: Keys that differ on every run and so cannot be compared between two builds.
VOLATILE_REPORT_KEYS: frozenset[str] = frozenset(
    {"report_id", "review_run_id", "created_at", "content_hash"}
)

CONFIG_DIR = Path("tests/config")
REVIEW_DATE = date(2026, 1, 1)


def build_fixture() -> dict[str, Any]:
    """Run a synthetic review, store it, then retrieve it the way the CLI does."""
    con = duckdb.connect(":memory:")
    try:
        _setup_full_db(con)
        config = load_config(CONFIG_DIR)
        result = run_review(config, con, CONFIG_DIR, review_date=REVIEW_DATE)
        if result.review_run_id is None:
            raise RuntimeError("review produced no run id")

        row = con.execute(
            "SELECT report_id, review_run_id, report_json, content_hash, created_at "
            "FROM review_reports WHERE review_run_id = ? OR report_id = ? LIMIT 1",
            [result.review_run_id, result.review_run_id],
        ).fetchone()
    finally:
        con.close()

    if row is None:
        raise RuntimeError(f"no stored report for {result.review_run_id!r}")

    # Envelope shape copied from src/dion/cli.py::report so the arms consume
    # exactly what the CLI would hand them.
    return {
        "ok": True,
        "command": "report",
        "run_type": "report",
        "run_id": row[1],
        "summary": {
            "status": "found",
            "report_id": row[0],
            "content_hash": row[3],
            "created_at": str(row[4]),
        },
        "data": {"report": json.loads(str(row[2]))},
    }
```

- [ ] **Step 4: Generate and commit the frozen fixture**

Run:
```bash
cd /Users/damian/IdeaProjects/Dion
mkdir -p tests/fixtures/design_seed_pilot tests/design_seed_pilot
touch tests/design_seed_pilot/__init__.py
uv run python -c "
import json, pathlib
from tests.design_seed_pilot.build_fixture import build_fixture
out = pathlib.Path('tests/fixtures/design_seed_pilot/review_report_envelope.json')
out.write_text(json.dumps(build_fixture(), indent=2, sort_keys=True) + '\n')
print('wrote', out)
"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/design_seed_pilot/test_fixture_fidelity.py -v`
Expected: PASS, 5 tests.

If `test_persistence_dropped_fields_are_absent` FAILS, that is the most important signal in this task: the persistence path preserves those fields after all, two of the four assumed gaps do not exist, and **Task 3 and the advance disclosures must be corrected before launch** rather than the test relaxed.

- [ ] **Step 6: Verify the repo gate still passes, then commit**

```bash
bash scripts/ci.sh
shasum -a 256 tests/fixtures/design_seed_pilot/review_report_envelope.json
git add tests/design_seed_pilot/ tests/fixtures/design_seed_pilot/
git commit -m "test: freeze the design-seed pilot fixture via store-then-retrieve"
```
Copy the printed sha256 into `pilot/HASHES.md` in Task 7.

---

### Task 3: Fixture adequacy

Fidelity and adequacy are separate. Task 2 proved the fixture is real; this proves it actually exercises every state the rubric scores. A real fixture that happens to contain no null fee scores nothing on "missing vs zero".

**Files (Dion repo):**
- Test: `tests/design_seed_pilot/test_fixture_adequacy.py`

**Interfaces:**
- Consumes: `tests/fixtures/design_seed_pilot/review_report_envelope.json` from Task 2.
- Produces: nothing consumed later; it is a gate.

- [ ] **Step 1: Write the failing test**

```python
# tests/design_seed_pilot/test_fixture_adequacy.py
"""The fixture must exercise every state the rubric scores.

A fixture can be faithfully retrieved and still be useless: if no order has a
null fee, the screen is never asked to distinguish missing from zero, and that
rubric dimension scores nothing for either arm.
"""
from __future__ import annotations

import json
from pathlib import Path

FIXTURE = Path("tests/fixtures/design_seed_pilot/review_report_envelope.json")


def _orders() -> list[dict]:
    report = json.loads(FIXTURE.read_text())["data"]["report"]
    return report.get("proposal_summary", {}).get("orders", [])


def test_has_enough_orders_to_show_density() -> None:
    assert len(_orders()) >= 5, "too few orders to exercise dense numeric display"


def test_has_a_missing_fee_distinct_from_zero() -> None:
    fees = [o.get("expected_fee_chf") for o in _orders()]
    assert any(f is None for f in fees), "no null fee — 'missing vs zero' is unscoreable"
    assert any(f == 0 or f == 0.0 for f in fees) or any(
        isinstance(f, (int, float)) for f in fees
    ), "no numeric fee to contrast the null against"


def test_has_both_order_directions() -> None:
    actions = {o.get("action") for o in _orders()}
    assert {"buy", "sell"} <= actions, f"missing a direction: {actions}"


def test_has_an_absent_field_distinct_from_a_null_one() -> None:
    """Missing value, absent field and unavailable evidence imply different UI."""
    report = json.loads(FIXTURE.read_text())["data"]["report"]
    assert "integrity_evidence" not in report or not report["integrity_evidence"], (
        "integrity_evidence must be absent/empty — it is the 'unavailable evidence' state"
    )
    assert any("expected_fee_chf" in o for o in _orders()), "need a present-but-null field"


def test_money_values_are_present_to_score_numeric_policy() -> None:
    vals = [o.get("cash_delta_chf") for o in _orders()]
    assert any(isinstance(v, (int, float)) for v in vals), "no money values to score"
```

- [ ] **Step 2: Run test to verify it fails or reveals a gap**

Run: `uv run pytest tests/design_seed_pilot/test_fixture_adequacy.py -v`
Expected: some cells FAIL. **This is the point of the task** — a failure here means the synthetic input must be enriched, not that the test is wrong.

- [ ] **Step 3: Enrich the synthetic input until every cell passes**

Edit the synthetic inputs `tests/review/_db_fixtures.py::_setup_full_db` seeds (and `tests/config/` if the universe is too small) so the generated review produces at least five orders, both directions, and at least one order whose fee is genuinely unavailable. **Do not patch the fixture JSON by hand** — that breaks Task 2's regeneration test and would make the fixture unreproducible.

- [ ] **Step 4: Regenerate the fixture and run both fixture test files**

Run:
```bash
uv run python -c "
import json, pathlib
from tests.design_seed_pilot.build_fixture import build_fixture
out = pathlib.Path('tests/fixtures/design_seed_pilot/review_report_envelope.json')
out.write_text(json.dumps(build_fixture(), indent=2, sort_keys=True) + '\n')
"
uv run pytest tests/design_seed_pilot/ -v
```
Expected: PASS, all tests in both files.

- [ ] **Step 5: Commit**

```bash
git add tests/design_seed_pilot/ tests/fixtures/design_seed_pilot/
git commit -m "test: assert the pilot fixture exercises every scored state"
```

---

### Task 4: Advance-disclosure freeze

Criterion (c) labels each contract-delta entry `supplied-in-advance` or `screen-discovered`. A self-label is not evidence, so the advance set must be frozen before either arm can see the task.

**Files:**
- Create: `openspec/changes/design-seed-capability/pilot/advance-disclosures.md`
- Test: covered by Task 5's `tests/test-pilot-artifacts.sh`

**Interfaces:**
- Consumes: Dion's `src/dion/proposal/report.py` and `CLAUDE.md` (to enumerate what the repo already reveals).
- Produces: the frozen disclosure list that Task 12 adjudicates `screen-discovered` claims against.

- [ ] **Step 1: Enumerate what the repo already reveals**

Run:
```bash
cd /Users/damian/IdeaProjects/Dion
grep -n 'Missing fee stays None' src/dion/proposal/report.py
grep -n 'comparators\|integrity_evidence' src/dion/proposal/report.py
sed -n '/## Numeric Policy/,/^## /p' CLAUDE.md
```
Every gap visible from these sources is `supplied-in-advance` by definition — an arm reading `report.py` learns them without building anything.

- [ ] **Step 2: Write the disclosure file**

```markdown
# Advance disclosures — frozen before launch

Anything below is `supplied-in-advance`. A contract-delta entry restating one of
these earns ZERO credit as `screen-discovered`, regardless of how the arm
describes finding it.

## Stated in the brief
- The screen renders an execution list from a frozen report envelope.
- The envelope is the only data source; no network, no database.

## Discoverable by reading the repo (therefore NOT screen-discovered)
- `expected_fee_chf` may be null; `src/dion/proposal/report.py` comments that a
  missing fee "stays None (not 0.0) so the renderer can show a visible gap
  rather than a plausible-but-wrong 'free trade'".
- `comparators` and `integrity_evidence` exist on `ReviewReport` and are absent
  from the stored JSON.
- The declared Numeric Policy: quantities DECIMAL(18,8), money DECIMAL(18,4),
  prices/FX DECIMAL(18,8) — and that serializers emit floats.
- Blocked runs store no report at all.
- Hold/block reasons are unstructured strings.

## What a `screen-discovered` claim requires
1. A named screen behaviour that the frozen envelope cannot support.
2. Evidence of WHEN the need arose (the prompt or edit that surfaced it).
3. A testable acceptance criterion for the proposed contract change.

Absent any of the three, the entry is recorded as unsubstantiated and scores
nothing.
```

- [ ] **Step 3: Commit**

```bash
git add openspec/changes/design-seed-capability/pilot/advance-disclosures.md
git commit -m "docs: freeze the pilot's advance disclosures before launch"
```

---

### Task 5: Rubric, brief and budget — with structural tests

Three frozen instrument artifacts, one test cycle: a reviewer would accept or reject them together, and each is meaningless without the others.

**Files:**
- Create: `openspec/changes/design-seed-capability/pilot/rubric.md`
- Create: `openspec/changes/design-seed-capability/pilot/brief.md`
- Create: `openspec/changes/design-seed-capability/pilot/budget.md`
- Test: `tests/test-pilot-artifacts.sh`

**Interfaces:**
- Consumes: `advance-disclosures.md` from Task 4.
- Produces: `rubric.md` with a machine-parseable `| id | dimension | source |` table (Task 11 sends it to judges verbatim); `brief.md` (Task 8 hands it to both arms unchanged).

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/test-pilot-artifacts.sh <<'EOF'
#!/bin/bash
# test-pilot-artifacts.sh — the frozen pilot instrument must satisfy the
# pre-registration structurally, not merely exist.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "${SCRIPT_DIR}/.." && pwd)/openspec/changes/design-seed-capability/pilot"
PASS=0; FAIL=0
_ok()  { printf '  PASS %s\n' "$1"; PASS=$(( PASS + 1 )); }
_bad() { printf '  FAIL %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

echo "test-pilot-artifacts"

for f in rubric.md brief.md budget.md advance-disclosures.md; do
    if [ -r "${P}/${f}" ]; then _ok "${f} exists"; else _bad "${f} missing"; fi
done

# --- the brief must not reveal the treatment -------------------------------
# An arm that can tell it is the seeded arm from the brief is not a control.
_leaks=0
for w in token styleguide "design system" "design seed" palette hypothesis "arm " seeded; do
    if grep -qi -- "${w}" "${P}/brief.md" 2>/dev/null; then
        _bad "brief leaks the treatment: '${w}'"; _leaks=1
    fi
done
[ "${_leaks}" -eq 0 ] && _ok "brief reveals no treatment vocabulary"

# --- the brief must state the embedding contract the egress check relies on -
if grep -q 'id="dion-report"' "${P}/brief.md" 2>/dev/null; then
    _ok "brief states the data-embedding contract"
else
    _bad "brief omits the id=\"dion-report\" embedding contract"
fi

# --- the rubric's dimension table ------------------------------------------
# Rows look like: | R1 | dimension text | source text |
_rows="$(grep -c '^| R[0-9]' "${P}/rubric.md" 2>/dev/null)" || _rows=0
if [ "${_rows}" -ge 5 ]; then _ok "rubric has ${_rows} scored dimensions"; else _bad "rubric has only ${_rows} dimensions (need >= 5)"; fi

# Every row must cite a source (third column non-empty).
_nosrc="$(awk -F'|' '/^\| R[0-9]/ { gsub(/^[ \t]+|[ \t]+$/,"",$4); if ($4 == "") c++ } END { print c+0 }' "${P}/rubric.md" 2>/dev/null)"
if [ "${_nosrc}" = "0" ]; then _ok "every dimension cites a source"; else _bad "${_nosrc} dimension(s) cite no source"; fi

# No scored dimension may reward resemblance to the thing under test.
_bans=0
_dims="$(awk -F'|' '/^\| R[0-9]/ { print $3 }' "${P}/rubric.md" 2>/dev/null)"
for w in token "design system" seed styleguide; do
    case "$(printf '%s' "${_dims}" | tr 'A-Z' 'a-z')" in
        *"${w}"*) _bad "rubric scores '${w}' — resemblance to the seed is not quality"; _bans=1 ;;
    esac
done
[ "${_bans}" -eq 0 ] && _ok "no dimension scores resemblance to the seed"

# --- budget must be operational, not aspirational --------------------------
_bmiss=0
for k in cap "stopping rule" timeout retry; do
    grep -qi -- "${k}" "${P}/budget.md" 2>/dev/null || { _bad "budget omits '${k}'"; _bmiss=1; }
done
[ "${_bmiss}" -eq 0 ] && _ok "budget defines cap, stopping rule, timeout and retry"

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
EOF
chmod +x tests/test-pilot-artifacts.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-pilot-artifacts.sh < /dev/null`
Expected: FAIL — `rubric.md missing`, `brief.md missing`, `budget.md missing`, and the structural cells failing with them.

- [ ] **Step 3: Write `rubric.md`**

```markdown
# Pilot scoring rubric — frozen before launch

Score EACH artifact independently, per dimension, citing concrete evidence from
that artifact. Only after both are scored may you state a comparative verdict.
Comparative-first scoring is not permitted.

Score each dimension 0-4: 0 absent, 1 poor, 2 adequate, 3 good, 4 excellent.

## Dimensions

| id | dimension | source |
|----|-----------|--------|
| R1 | Money and quantities are shown at a consistent, declared precision, with no floating-point artifacts | Host repo's declared numeric policy: quantities DECIMAL(18,8), money DECIMAL(18,4) |
| R2 | A missing value is visually distinct from zero and from an empty set | Host repo comment: a missing fee "stays None (not 0.0) so the renderer can show a visible gap rather than a plausible-but-wrong 'free trade'" |
| R3 | Nothing is fabricated, interpolated, or inferred beyond the supplied data | Host repo principle: "never invent prices, returns, or holdings" |
| R4 | Visual hierarchy: the reader's eye reaches the most consequential figure first | Independent reviewer's stated criterion |
| R5 | Readability of dense financial values: alignment, grouping, and scanability across rows | Independent reviewer's stated criterion |
| R6 | Consistency of repeated elements and of state treatments across the screen | Independent reviewer's stated criterion |
| R7 | Honest handling of missing information: absence is communicated, never papered over | Independent reviewer's stated criterion |
| R8 | Fidelity: every displayed value traces to the supplied data | This pilot |

## Not scored

Presence or absence of a design system, use of CSS custom properties, palette
provenance, or resemblance to any reference. Quality is never defined as looking
like a particular thing.

## Output required

For each artifact, per dimension: the score and the specific evidence.
Then: which artifact scored higher overall, and on which dimensions they differ
most. If you cannot separate them, say so.
```

- [ ] **Step 4: Write `brief.md`**

```markdown
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
```

- [ ] **Step 5: Write `budget.md`**

```markdown
# Budget rules — frozen before launch

Identical for both arms. The clock starts at dispatch, BEFORE any adoption work,
so preparation cannot become unbudgeted effort.

- **Cap:** 60 tool calls per arm.
- **Stopping rule:** the arm stops at the cap, or when it reports done, whichever
  comes first. Work in progress at the cap is submitted as-is.
- **Timeout:** 45 minutes wall clock per arm.
- **Retry allowance:** none within a run. One whole-arm rerun is permitted ONLY
  for an infrastructure fault (harness crash, tool unavailable), declared and
  recorded before the rerun. Never for an unsatisfying result.
- **Recorded per arm:** tool calls used, wall clock used, and — for the seeded
  arm — the split between adoption and implementation.
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test-pilot-artifacts.sh < /dev/null`
Expected: PASS. If the brief-leak cell fails, the brief names the treatment — reword it; do not relax the test.

- [ ] **Step 7: Commit**

```bash
git add openspec/changes/design-seed-capability/pilot/ tests/test-pilot-artifacts.sh
git commit -m "feat: freeze the pilot rubric, brief and budget with structural tests"
```

---

### Task 6: Deterministic browser capture

The Python gate proves the generator sound and says nothing about whether the HTML renders. Judging needs matched screenshots, and they must be reproducible or they are not evidence.

**Files:**
- Create: `scripts/pilot-capture.sh`
- Test: `tests/test-pilot-capture.sh`

**Interfaces:**
- Consumes: any local HTML file.
- Produces: `scripts/pilot-capture.sh <input.html> <out-dir>` writing `light.png` and `dark.png`. Task 10 calls it for both artifacts.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/test-pilot-capture.sh <<'EOF'
#!/bin/bash
# test-pilot-capture.sh — captures must be deterministic, or they are not evidence.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAP="${ROOT}/scripts/pilot-capture.sh"
PASS=0; FAIL=0
_ok()  { printf '  PASS %s\n' "$1"; PASS=$(( PASS + 1 )); }
_bad() { printf '  FAIL %s\n' "$1"; FAIL=$(( FAIL + 1 )); }
_skip(){ printf '  SKIP %s\n' "$1"; }

echo "test-pilot-capture"

if [ ! -x "${CAP}" ]; then
    _bad "scripts/pilot-capture.sh is missing or not executable"
    printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"; [ "${FAIL}" -eq 0 ]; exit
fi

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
cat > "${TMP}/page.html" <<'HTML'
<html><head><style>
:root { color-scheme: light dark; }
body { background:#fff; color:#111; font-family: system-ui, sans-serif; }
@media (prefers-color-scheme: dark) { body { background:#111; color:#eee; } }
</style></head><body><h1>capture probe</h1><p>1234.5678</p></body></html>
HTML

if ! "${CAP}" "${TMP}/page.html" "${TMP}/run1" >/dev/null 2>&1; then
    _skip "capture backend unavailable on this machine — cannot assert determinism"
    printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"; [ "${FAIL}" -eq 0 ]; exit
fi
_ok "capture produced output"

for f in light.png dark.png; do
    [ -s "${TMP}/run1/${f}" ] && _ok "${f} is non-empty" || _bad "${f} missing or empty"
done

"${CAP}" "${TMP}/page.html" "${TMP}/run2" >/dev/null 2>&1
if cmp -s "${TMP}/run1/light.png" "${TMP}/run2/light.png"; then
    _ok "light capture is byte-identical across runs"
else
    _bad "light capture is NOT deterministic"
fi
if cmp -s "${TMP}/run1/dark.png" "${TMP}/run2/dark.png"; then
    _ok "dark capture is byte-identical across runs"
else
    _bad "dark capture is NOT deterministic"
fi
if cmp -s "${TMP}/run1/light.png" "${TMP}/run1/dark.png"; then
    _bad "light and dark captures are identical — colour scheme is not being applied"
else
    _ok "light and dark captures differ"
fi

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
EOF
chmod +x tests/test-pilot-capture.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-pilot-capture.sh < /dev/null`
Expected: FAIL — `scripts/pilot-capture.sh is missing or not executable`.

- [ ] **Step 3: Write minimal implementation**

```bash
cat > scripts/pilot-capture.sh <<'EOF'
#!/bin/bash
# pilot-capture.sh — deterministic light+dark screenshots of a local HTML file.
#
# Instrument-side only. This is deliberately NOT added to the subject repo: the
# pilot's argument is that the screen needs no frontend toolchain, and standing
# one up in the subject to take its picture would undercut that.
#
# Frozen: viewport 1440x900, deviceScaleFactor 1, animations disabled, both
# colour schemes. Fonts are the machine's; the set in use is recorded alongside.
set -u
_die() { printf 'pilot-capture: %s\n' "$*" >&2; exit 1; }
[ $# -eq 2 ] || _die "usage: pilot-capture.sh <input.html> <out-dir>"
_IN="$1"; _OUT="$2"
[ -r "${_IN}" ] || _die "unreadable input: ${_IN}"
command -v npx >/dev/null 2>&1 || _die "npx unavailable"
mkdir -p "${_OUT}" || _die "cannot create ${_OUT}"

_ABS="$(cd "$(dirname "${_IN}")" && pwd)/$(basename "${_IN}")"

cat > "${_OUT}/.capture.mjs" <<'JS'
import { chromium } from 'playwright';
const [url, outDir] = process.argv.slice(2);
const browser = await chromium.launch();
for (const scheme of ['light', 'dark']) {
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
    colorScheme: scheme,
    reducedMotion: 'reduce',
  });
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'load' });
  await page.addStyleTag({ content: '*,*::before,*::after{animation:none!important;transition:none!important;caret-color:transparent!important}' });
  await page.screenshot({ path: `${outDir}/${scheme}.png`, fullPage: true, animations: 'disabled' });
  await ctx.close();
}
await browser.close();
JS

npx --yes playwright@1.47.0 install chromium >/dev/null 2>&1 || true
npx --yes --package playwright@1.47.0 node "${_OUT}/.capture.mjs" "file://${_ABS}" "${_OUT}" \
    || _die "capture failed"

rm -f "${_OUT}/.capture.mjs"
printf 'captured light.png and dark.png in %s\n' "${_OUT}"
EOF
chmod +x scripts/pilot-capture.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-pilot-capture.sh < /dev/null`
Expected: PASS. If the backend is unavailable the test SKIPs rather than passing vacuously — in that case resolve the backend before launch; a pilot without captures cannot judge rendering.

- [ ] **Step 5: Commit**

```bash
git add scripts/pilot-capture.sh tests/test-pilot-capture.sh
git commit -m "feat: deterministic light and dark capture for pilot artifacts"
```

---

### Task 7: Hash and push the frozen instrument

Git is an audit trail, not a trusted timestamp — local history and dates are rewritable. Pushing before launch is what makes "pre-registered" mean something.

**Files:**
- Create: `openspec/changes/design-seed-capability/pilot/HASHES.md`

**Interfaces:**
- Consumes: every artifact from Tasks 2-6.
- Produces: the recorded hashes Task 12 cites when reporting the result.

- [ ] **Step 1: Compute every hash**

Run:
```bash
cd /Users/damian/IdeaProjects/auto-claude-skills
P=openspec/changes/design-seed-capability/pilot
shasum -a 256 "$P"/rubric.md "$P"/brief.md "$P"/budget.md "$P"/advance-disclosures.md
shasum -a 256 /Users/damian/IdeaProjects/Dion/tests/fixtures/design_seed_pilot/review_report_envelope.json
git rev-parse HEAD
cd /Users/damian/IdeaProjects/Dion && git rev-parse HEAD
```

- [ ] **Step 2: Record them**

Also record this MEASURED fact, which replaces a caveat: Dion's `#211` merged during pre-launch (`4f2ae22`, 220 lines of `src/dion/optimizer/policy.py`). The fixture was regenerated on top of it in a throwaway worktree and diffed: **the report content is byte-identical**; only `run_id`, `summary.created_at` and `summary.report_id` differ. So the pinned base `3fbd89a` is content-equivalent to post-`#211` main for this fixture — state it as a measurement naming `4f2ae22`, not as "measured at 3fbd89a, read accordingly".

Write `openspec/changes/design-seed-capability/pilot/HASHES.md` with one row per artifact — path, sha256, and the commit each was frozen at — plus both repos' base commits. Add a line stating the date and that nothing below may change without making this v2.

- [ ] **Step 3: Verify a REAL capture works — the suite cannot catch this**

`tests/test-pilot-capture.sh` SKIPs and exits 0 when no capture backend is available, so `run-tests.sh` going green does **not** prove captures are possible. Judging needs matched screenshots; a launch with no capture ability would only be discovered after both arms had spent their budget.

Run:
```bash
cd /tmp/acs-pilot
T=$(mktemp -d)
cat > "$T/probe.html" <<'HTML'
<html><head><style>
:root { color-scheme: light dark; }
body { background:#fff; color:#111; font-family: system-ui, sans-serif; }
@media (prefers-color-scheme: dark) { body { background:#111; color:#eee; } }
</style></head><body><h1>launch probe</h1><p>1234.5678</p></body></html>
HTML
bash scripts/pilot-capture.sh "$T/probe.html" "$T/out" || { echo "CAPTURE FAILED — DO NOT LAUNCH"; exit 1; }
[ -s "$T/out/light.png" ] && [ -s "$T/out/dark.png" ] || { echo "MISSING PNGs — DO NOT LAUNCH"; exit 1; }
cmp -s "$T/out/light.png" "$T/out/dark.png" && { echo "LIGHT == DARK, colour-scheme emulation dead — DO NOT LAUNCH"; exit 1; }
echo "capture verified: two differing PNGs produced"
rm -rf "$T"
```
Expected: `capture verified: two differing PNGs produced`. **A failure here blocks launch** — it is not advisory. Record the outcome in `HASHES.md`.

- [ ] **Step 4: Verify the full suite is green before launch**

Run: `bash tests/run-tests.sh`
Expected: PASS. A red suite here blocks every routing push repo-wide and must be resolved before the arms run, not after.

- [ ] **Step 5: Commit and push**

```bash
git add openspec/changes/design-seed-capability/pilot/HASHES.md
git commit -m "docs: record frozen pilot artifact hashes before launch"
git push -u origin design-seed-pilot-protocol
```
The push is the pre-registration. **Do not proceed to Task 8 until it has landed on the remote.**

---

### Task 8: Launch both arms

**Files:**
- Create: two Dion worktrees (disposable, outside both repos).

**Interfaces:**
- Consumes: `brief.md`, `budget.md`, the frozen fixture, and (arm S only) `assets/design-seed/`.
- Produces: `artifacts/execution-list.html` and `artifacts/contract-delta.md` in each worktree; arm S additionally produces an adoption record.

- [ ] **Step 0: Re-measure the private store immediately before dispatch**

The `private_data` leg was measured hours before launch, and a measurement that
old is a claim, not a precondition. Re-run it at dispatch time and record the
output in the consumption record:

```bash
find /tmp/dion-pilot /tmp/pilot-arm-c /tmp/pilot-arm-s -name '*.duckdb' 2>/dev/null
```
Expected: no output. **Any hit halts the launch.** `dion report --db-path`
defaults to `data/dion.duckdb`, so a private store reachable from an arm's
worktree puts the omitted-flag path one typo away from the happy path.

- [ ] **Step 1: Create the worktrees**

**Not in the shared checkout.** `/Users/damian/IdeaProjects/Dion` is on
`main @ 4f2ae22`, which is NOT the pre-registered lineage — it carries `#211`,
explicitly unreachable from the pinned fixture base. `git rev-parse HEAD` there
silently launches both arms against the wrong subject. Worktrees also must not
be created inside the shared repo; concurrent sessions live there.

Operate in `/tmp/dion-pilot`, and assert the lineage rather than trusting a
checkout:

```bash
cd /tmp/dion-pilot
PINNED=3fbd89a                     # the fixture's pre-registered base
BASE=$(git rev-parse HEAD)         # design-seed-pilot HEAD, per HASHES.md
if ! git merge-base --is-ancestor "$PINNED" "$BASE"; then echo "LINEAGE BROKEN"; exit 1; fi
if git merge-base --is-ancestor 4f2ae22 "$BASE" 2>/dev/null; then echo "#211 LEAKED IN"; exit 1; fi
git worktree add -b pilot-arm-c /tmp/pilot-arm-c "$BASE"
git worktree add -b pilot-arm-s /tmp/pilot-arm-s "$BASE"
```

**Why `BASE` is the branch HEAD and not the literal `3fbd89a`.** `brief.md`
tells the arms to read
`tests/fixtures/design_seed_pilot/review_report_envelope.json`, which does not
exist at `3fbd89a` — it was created on this branch — and the arms' capability
boundary (`.claude/settings.json` plus `.claude/hooks/pilot-arm-deny.py`) lives
there too. Checking out the literal pinned commit would launch arms with
neither. The four commits between `3fbd89a` and the branch HEAD touch only
`tests/design_seed_pilot/` and the fixture — **no `src/` change** — so the
subject code the arms build against IS the pinned base. The two assertions
above are what make that a checked property rather than an assumption.

- [ ] **Step 2: Adopt the seed UNADAPTED into arm S only**

```bash
cd /Users/damian/IdeaProjects/auto-claude-skills
cp -R assets/design-seed/presets/default /tmp/pilot-arm-s/design
cp assets/design-seed/styleguide.md assets/design-seed/reference.html /tmp/pilot-arm-s/design/
cp -R assets/design-seed/checks /tmp/pilot-arm-s/design/checks
cd /tmp/pilot-arm-s && git add design && git commit -m "chore: adopt design seed (unadapted)"
```
Then append the `ADOPT.md` pointer line to `/tmp/pilot-arm-s/CLAUDE.md` and `/tmp/pilot-arm-s/AGENTS.md`. **Change no token value** — adaptation is arm S's measured work, not yours.

- [ ] **Step 3: Verify arm C is genuinely unseeded**

Run: `ls /tmp/pilot-arm-c/design 2>&1; grep -ric 'design/styleguide\|token' /tmp/pilot-arm-c/CLAUDE.md /tmp/pilot-arm-c/AGENTS.md`
Expected: `No such file or directory`, and zero matches. A leaked pointer makes the control arm not a control.

- [ ] **Step 4: Dispatch both arms in one message**

Dispatch two `general-purpose` subagents concurrently. Each receives the verbatim contents of `brief.md` plus its worktree path and the budget cap. **Tell neither that another arm exists, that a design system exists, or what is being tested.** Arm S's prompt differs from arm C's only by the addition of its own repo-standard instruction to consult `design/styleguide.md` and run `design/checks/token-lint.sh` — the same pointer any adopting project would have.

**On "give neither agent egress tools" — you cannot.** `general-purpose` has
tool access `*` and the Agent tool exposes no tool-restriction parameter, so
that sentence described an intention, not an action. The boundary is the
`PreToolUse` deny hook carried in each worktree
(`.claude/hooks/pilot-arm-deny.py`, wired in `.claude/settings.json`, inherited
by both worktrees because both files are tracked). It refuses `WebFetch`,
`WebSearch` and the whole `mcp__` namespace by tool name, and refuses reads of
`~/.config/gh/hosts.yml`, `~/.ssh`, `~/.claude.json` and
`~/.claude/projects/*/memory/` across every path-bearing tool. **Residual,
named rather than papered over: Bash-level network egress is NOT closed** —
enumerating it is unbounded. Confirm the hook is live in both worktrees before
dispatching:

```bash
for w in /tmp/pilot-arm-c /tmp/pilot-arm-s; do
    printf '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"}}' \
        | python3 "$w/.claude/hooks/pilot-arm-deny.py"; echo "$w -> rc=$?"
done
```
Expected: `rc=2` for both, with a `pilot-arm-deny:` line on stderr. An `rc=0`,
or an `rc=2` with no marker, means the boundary is not there.

- [ ] **Step 5: Record consumption**

For each arm record tool calls used, wall clock, and whether it hit the cap. For arm S also record the adoption/implementation split and the freeze commit sha. Write to `pilot/results/arm-consumption.md`.

- [ ] **Step 6: Commit the evidence**

```bash
cd /Users/damian/IdeaProjects/auto-claude-skills
git add openspec/changes/design-seed-capability/pilot/results/
git commit -m "docs: record pilot arm consumption"
```

---

### Task 9: Collect artifacts and run the egress gate

**Files:**
- Create: `openspec/changes/design-seed-capability/pilot/results/artifact-a.html`, `artifact-b.html`
- Create: `openspec/changes/design-seed-capability/pilot/results/label-mapping.json`

**Interfaces:**
- Consumes: both worktrees' `artifacts/`, `scripts/pilot-egress-check.sh` from Task 1.
- Produces: two blinded artifacts plus the mapping Task 12 reads.

- [ ] **Step 1: Write the label mapping BEFORE anything is renamed**

```bash
cd /Users/damian/IdeaProjects/auto-claude-skills
R=openspec/changes/design-seed-capability/pilot/results
mkdir -p "$R"
# Randomise which arm becomes A.
if [ $(( RANDOM % 2 )) -eq 0 ]; then A=s; B=c; else A=c; B=s; fi
printf '{"artifact-a":"arm-%s","artifact-b":"arm-%s","written_at":"%s"}\n' \
    "$A" "$B" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$R/label-mapping.json"
cat "$R/label-mapping.json"
```

- [ ] **Step 2: Copy under blinded names and strip provenance**

Copy each arm's HTML to `artifact-a.html` / `artifact-b.html` per the mapping, then strip HTML comments and any generator header naming a path, arm, or the seed. **Do not alter visible design** — semantic class or variable names stay exactly as authored.

- [ ] **Step 3: Run the egress gate on the STRIPPED artifacts**

**The order here is the whole point.** Running the gate on the arms' worktree
files and then stripping them certifies one set of bytes and ships another —
the strip happens between the check and the send, so the gate has an opinion
about a file nobody transmits. The check runs on the bytes that actually leave.

```bash
F=/tmp/dion-pilot/tests/fixtures/design_seed_pilot/review_report_envelope.json
bash scripts/pilot-egress-check.sh "$R/artifact-a.html" "$F"; echo "artifact-a exit=$?"
bash scripts/pilot-egress-check.sh "$R/artifact-b.html" "$F"; echo "artifact-b exit=$?"
```
Expected: both exit 0. **A non-zero exit halts the pilot** — investigate before anything is sent. This is the safety-stop, not a warning. If a strip broke the data block, that is exactly what this ordering is for; fix the strip, do not re-run the check against the pre-strip file.

The fixture path is `/tmp/dion-pilot`, not the shared checkout: the fixture
lives on the pilot branch and does not exist on `main`.

- [ ] **Step 4: Verify the blinding**

```bash
grep -ril 'arm-s\|arm-c\|pilot-arm\|design-seed\|styleguide' "$R"/artifact-*.html && echo "LEAK" || echo "no provenance leak"
```
Expected: `no provenance leak`.

- [ ] **Step 5: Capture both artifacts**

```bash
bash scripts/pilot-capture.sh "$R/artifact-a.html" "$R/capture-a"
bash scripts/pilot-capture.sh "$R/artifact-b.html" "$R/capture-b"
```

- [ ] **Step 6: Commit**

```bash
git add openspec/changes/design-seed-capability/pilot/results/
git commit -m "docs: blinded pilot artifacts, captures and label mapping"
```

---

### Task 10: Judge call 1 (order A/B)

**Files:**
- Create: `openspec/changes/design-seed-capability/pilot/results/judge-1.md`

**Interfaces:**
- Consumes: `rubric.md`, both blinded artifacts, both capture sets.
- Produces: one judge response. Task 11 produces the reversed-order second.

- [ ] **Step 1: Build the judging package**

Compose a package containing, in this order: the verbatim `rubric.md`; then artifact A's HTML source; then artifact B's HTML source. **The package must not mention** seeds, arms, design systems, a hypothesis, this pilot, or that anything is being compared beyond the two artifacts in front of it.

- [ ] **Step 2: Freeze and get consent**

```bash
bash scripts/consult-dispatch.sh prepare codex <package-file>
```
Then ask the user with the exact `AskUserQuestion` shape the output prints — `Do not send` first, the complete package as the approve option's preview.

- [ ] **Step 3: Send and record**

```bash
bash scripts/consult-dispatch.sh send <digest>
```
Save the answer verbatim to `pilot/results/judge-1.md`, with the pinned model and version recorded at the top.

- [ ] **Step 4: Commit**

```bash
git add openspec/changes/design-seed-capability/pilot/results/judge-1.md
git commit -m "docs: pilot judge response 1 (order A/B)"
```

---

### Task 11: Judge call 2 (order B/A)

Identical to Task 10 with the presentation order reversed, as a fresh consultation. This measures order sensitivity and some judging variance — it does not make the judges independent, and no amount of judging compensates for one artifact per arm.

**Files:**
- Create: `openspec/changes/design-seed-capability/pilot/results/judge-2.md`

**Interfaces:**
- Consumes: the same rubric and artifacts.
- Produces: the second judge response Task 12 adjudicates against the first.

- [ ] **Step 1: Build the reversed package**

Same construction as Task 10, but artifact **B**'s source precedes artifact **A**'s. Relabel them within this package as the first and second artifact so the judge is not told which is "A". Same prohibition on framing vocabulary.

- [ ] **Step 2: Freeze, consent, send**

```bash
bash scripts/consult-dispatch.sh prepare codex <package-file>
# ask the user, then:
bash scripts/consult-dispatch.sh send <digest>
```

- [ ] **Step 3: Record the provenance question**

After scoring is recorded, and only after, note whether the judge volunteered any inference about where either artifact came from.

- [ ] **Step 4: Commit**

```bash
git add openspec/changes/design-seed-capability/pilot/results/judge-2.md
git commit -m "docs: pilot judge response 2 (order B/A)"
```

---

### Task 12: Adjudicate against the pre-registered rules

The rules were fixed in Task 7 and pushed. Apply them; do not revise them.

**Files:**
- Create: `openspec/changes/design-seed-capability/pilot/results/RESULT.md`
- Modify: `openspec/changes/design-seed-capability/design.md` (append the outcome)

**Interfaces:**
- Consumes: `judge-1.md`, `judge-2.md`, `label-mapping.json`, `arm-consumption.md`, both `contract-delta.md` files, arm S's adoption record.
- Produces: the recorded result.

- [ ] **Step 1: Unblind and apply the outcome rule**

Read `label-mapping.json`. Determine which arm each judge favoured, then select exactly one pre-registered outcome:

1. Both judges favour S → observed comparison favouring the seeded workflow.
2. Both judges favour C → recorded as such; interpretable because the treatment is the whole first-use workflow.
3. Judges split → **judge-sensitive / inconclusive. Make no third call.**
4. An arm failed → reported visibly; rerun only for a declared infrastructure fault.
5. Process-gate failure on (a) or (b) → reported separately from the screen score; the run is not dropped.

- [ ] **Step 2: Score the process gates separately**

Criterion (a): did arm S record an adaptation with original rule, predicted failure, the change, and a distinguishing check — **or** an explicit "no justified adaptation needed"? Both are valid. Criterion (b): is there a `design/` freeze commit preceding the first implementation commit? Criterion (c): for each arm, how many contract-delta entries are substantiated `screen-discovered` under Task 4's three-part requirement? Entries restating an advance disclosure score zero.

- [ ] **Step 3: Write `RESULT.md`**

State the outcome, the per-dimension scores from both judges, the process-gate results, consumption figures, and every frozen hash from `HASHES.md`. Then state the claim in exactly this form, adjusted only for which arm won:

> On this task, fixture, model configuration and resource cap, the
> seeded-adoption run received a higher blinded rubric score than the comparator
> run, and the required process gates were satisfied. This single pair does not
> distinguish a repeatable workflow advantage from generation variation.

Add a "What this does not establish" section: how often S wins; whether the seed's rules rather than the workflow caused any difference; whether an adaptation improved anything.

- [ ] **Step 4: Verify no overclaim**

Run: `grep -in 'proves\|demonstrates that the seed\|the seed improves\|validates the default' openspec/changes/design-seed-capability/pilot/results/RESULT.md`
Expected: no matches. Any hit is an overclaim the pre-registration forbids — rewrite it.

- [ ] **Step 5: Run the suite and commit**

```bash
bash tests/run-tests.sh
git add openspec/changes/design-seed-capability/
git commit -m "docs: record the design-seed pilot result"
```

---

### Task 13: Clean up and decide the capability's disposition

**Files:**
- Modify: `openspec/changes/design-seed-capability/design.md`

- [ ] **Step 1: Reap the worktrees**

```bash
cd /Users/damian/IdeaProjects/Dion
git worktree remove /tmp/pilot-arm-c --force
git worktree remove /tmp/pilot-arm-s --force
git worktree prune
git branch -D pilot-arm-c pilot-arm-s
```

- [ ] **Step 2: Decide arm S's screen separately**

Whether Dion keeps the seeded screen is a normal Dion change on its own merits, reviewed as Dion code. It is NOT part of the evidence claim and must not be merged as though the pilot authorised it. Arm C's output is evidence only and is never proposed for merge.

- [ ] **Step 3: Present the archive decision**

The change archives with the pilot. Present to the user: archive `design-seed-capability` now, or hold it open pending a second pair. Do not archive unilaterally — outcome 3 (inconclusive) in particular may argue for holding.

- [ ] **Step 4: Commit**

```bash
git add openspec/changes/design-seed-capability/
git commit -m "docs: close out the design-seed pilot"
```
