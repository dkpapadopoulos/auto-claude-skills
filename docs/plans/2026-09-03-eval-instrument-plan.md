# Behavioral-eval instrument fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans or
> superpowers:subagent-driven-development. Steps use `- [ ]` for tracking.

**Goal:** Stop `tests/run-eval-pack.sh` reporting sampling noise as skill
regressions, and make the model it measured auditable.

**Architecture:** Keep the existing per-assertion measurement untouched.
Change only what happens *after* measurement: record counts and provenance in
the baseline, skip diffing entirely when provenance differs, and require a
degradation to persist across two consecutive runs before it is reported.

**Tech Stack:** Bash 3.2 (macOS `/bin/bash`), jq, GitHub Actions.

**Spec:** `docs/plans/2026-09-03-eval-instrument-design.md`

## Global Constraints

- Bash 3.2 compatible. No associative arrays. No quoted operands in `$(( ))`.
- `tests/run-eval-pack.sh` exit contract is load-bearing and must not change:
  0 clean, 1 regression/safety-fail, 2 guard/tooling failure.
- Existing assertions in `tests/test-run-eval-pack.sh` must all stay green.
- Baseline reads must tolerate a v1 baseline (no counts, no provenance)
  without crashing — degrade, never exit 2.
- Reports are STRUCTURED ONLY: ids, verdicts, rates, classifications. Never
  raw subject or judge text (agent-safety-review constraint).

---

### Task 1: Baseline schema v2 — counts and provenance

**Files:**
- Modify: `tests/run-eval-pack.sh` (the `--update-baseline` writer, ~line 243-268)
- Modify: `tests/run-behavioral-evals.sh` (model extraction, line 420)
- Test: `tests/test-run-eval-pack.sh`

**Interfaces:**
- Produces: baseline key `schema: 2`; top-level `provenance` object
  `{subject_models: [string], judge_model: string, cli_version: string}`;
  per-assertion `pass` and `n` integers alongside the existing
  `classification` string.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing test** — append to `tests/test-run-eval-pack.sh`:

```bash
echo "-- baseline v2: records counts and provenance --"
run_pack --pack "${FIX}/pack.json" --baseline "${NEW_BASELINE}" --update-baseline
assert_contains "baseline declares schema 2" '"schema": 2' "$(cat "${NEW_BASELINE}")"
assert_contains "baseline records per-assertion pass count" '"pass":' "$(cat "${NEW_BASELINE}")"
assert_contains "baseline records per-assertion n" '"n":' "$(cat "${NEW_BASELINE}")"
assert_contains "baseline records provenance" '"provenance"' "$(cat "${NEW_BASELINE}")"
assert_contains "provenance names the subject models" '"subject_models"' "$(cat "${NEW_BASELINE}")"
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: FAIL — the writer emits neither `schema` nor `pass`/`n` nor `provenance`.

- [ ] **Step 3: Record the full modelUsage map, not `keys[0]`**

In `tests/run-behavioral-evals.sh` line 420, replace the alphabetical-first
extraction so the artifact keeps every model that did work:

```bash
    MODEL="$(printf '%s' "${CLAUDE_JSON}" | jq -r '(.model // (.modelUsage | keys[0]? // empty)) // "unknown"')"
    MODELS_ALL="$(printf '%s' "${CLAUDE_JSON}" | jq -c '((.modelUsage // {}) | keys) // []')"
```

Add `--argjson models_all "${MODELS_ALL}"` to the artifact-writing jq at
line ~599 and emit `models_all: $models_all` beside the existing `model`.
`model` stays for backward compatibility — readers are not changed here.

- [ ] **Step 4: Emit schema, counts and provenance in the baseline writer**

In `tests/run-eval-pack.sh`, inside the `--update-baseline` block, add
`"schema": 2,` next to `"variance"`, add the provenance object built from
`${MODEL}`, `${JUDGE_MODEL:-}` and `$(claude --version 2>/dev/null | head -1)`,
and extend the per-assertion jq to carry the counts it already has in scope:

```jq
assertions: [.value.assertions[] | {
    index, kind, description,
    pass: .pass,
    n: (.pass + .fail),
    classification: ( ... unchanged ... )
}]
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: PASS, including every pre-existing assertion.

- [ ] **Step 6: Commit**

```bash
git add tests/run-eval-pack.sh tests/run-behavioral-evals.sh tests/test-run-eval-pack.sh
git commit -m "feat: baseline schema v2 records per-assertion counts and run provenance"
```

---

### Task 2: Provenance mismatch skips the diff

**Files:**
- Modify: `tests/run-eval-pack.sh` (before the scenario compare loop, ~line 172)
- Test: `tests/test-run-eval-pack.sh`

**Interfaces:**
- Consumes: Task 1's `provenance.subject_models` and `provenance.cli_version`.
- Produces: report section `## RECALIBRATION EVENT — comparison skipped`;
  exit 0 on mismatch.

- [ ] **Step 1: Write the failing test**

```bash
echo "-- provenance mismatch: diff is skipped, not reported as regression --"
jq '.provenance.subject_models = ["some-other-model"]' "${NEW_BASELINE}" > "${TMP}/prov.json"
run_pack --pack "${FIX}/pack.json" --baseline "${TMP}/prov.json" --report "${REPORT}"
assert_equals "provenance mismatch exits 0" "0" "${exit_code}"
assert_contains "report names the recalibration event" "RECALIBRATION EVENT" "$(cat "${REPORT}")"
assert_not_contains "no regressions claimed on mismatch" "Regressions vs baseline" "$(cat "${REPORT}")"
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: FAIL — currently the run diffs regardless of provenance and can exit 1.

- [ ] **Step 3: Implement the skip**

Before the compare loop, read `.provenance` from the baseline. When the
baseline declares provenance (v2) and it differs from this run's, set
`PROVENANCE_MISMATCH=1`. When set: emit the recalibration section, skip
populating `REGRESSIONS`, and leave `SAFETY_FAILS` behaviour untouched — a
safety gate still fires, because a model change is not a licence to ship an
unapproved-write regression. A v1 baseline (no `provenance`) never mismatches.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/run-eval-pack.sh tests/test-run-eval-pack.sh
git commit -m "feat: skip baseline diffing on a provenance mismatch"
```

---

### Task 3: Persistence filter — two consecutive runs

**Files:**
- Modify: `tests/run-eval-pack.sh` (new `--previous <path>` option; compare loop)
- Modify: `.github/workflows/behavioral-evals.yml` (download prior artifacts)
- Test: `tests/test-run-eval-pack.sh`

**Interfaces:**
- Consumes: a previous run's `measured.json`-shaped file via `--previous`.
- Produces: a regression row only when the assertion degraded against
  baseline in BOTH the previous and the current run.

- [ ] **Step 1: Write the failing test**

```bash
echo "-- persistence: a first-time degradation is not reported --"
run_pack --pack "${FIX}/pack.json" --baseline "${FIX}/baseline-stable.json" \
         --previous "${FIX}/previous-clean.json" --report "${REPORT}"
assert_equals "single-run degradation exits 0" "0" "${exit_code}"
assert_not_contains "no regression on first occurrence" "REGRESSED" "$(cat "${REPORT}")"

echo "-- persistence: a repeated degradation IS reported --"
run_pack --pack "${FIX}/pack.json" --baseline "${FIX}/baseline-stable.json" \
         --previous "${FIX}/previous-degraded.json" --report "${REPORT}"
assert_equals "repeated degradation exits 1" "1" "${exit_code}"
assert_contains "regression reported on second occurrence" "REGRESSED" "$(cat "${REPORT}")"
```

- [ ] **Step 2: Create the two fixtures**

`tests/fixtures/eval-pack-runner/previous-clean.json` — prior counts at the
baseline's own rates. `previous-degraded.json` — prior counts already below
baseline for the same assertion the pack fixture fails.

- [ ] **Step 3: Run it and confirm it fails**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: FAIL — `--previous` is not a recognised option.

- [ ] **Step 4: Implement `--previous` and the AND condition**

Parse `--previous`. In the compare loop, where `delta="REGRESSED"` is set,
additionally require that the same assertion was also below its baseline rank
in the previous file. With no `--previous`, behaviour is unchanged (report as
today) so local runs and the first CI run after this lands still work.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: PASS.

- [ ] **Step 6: Wire the workflow to fetch the prior run**

Add a step before "Run eval pack" that downloads the previous successful
run's `behavioral-eval-artifacts` (30-day retention, weekly cadence) into
`tests/prev/`, tolerating absence, and pass `--previous tests/prev/measured.json`
only when the file exists.

- [ ] **Step 7: Commit**

```bash
git add tests/run-eval-pack.sh tests/test-run-eval-pack.sh \
        tests/fixtures/eval-pack-runner/previous-*.json \
        .github/workflows/behavioral-evals.yml
git commit -m "feat: require a degradation to persist across two runs before reporting"
```

---

### Task 4: Honest classification thresholds and intervals

**Files:**
- Modify: `tests/run-eval-pack.sh:161-162`, `tests/run-behavioral-evals.sh:264-265`
- Test: `tests/test-run-eval-pack.sh`

**Interfaces:**
- Produces: `classify()` whose "stable" boundary matches the documented
  >=90%; report column carrying a Clopper-Pearson 95% interval per assertion.

- [ ] **Step 1: Write the failing test**

```bash
echo "-- classification honours the documented >=90% boundary --"
assert_equals "2 of 3 is NOT stable at the documented 90% bar" "flaky" "$(classify_probe 2 3)"
assert_equals "3 of 3 is stable" "stable" "$(classify_probe 3 3)"
assert_equals "0 of 3 is broken" "broken" "$(classify_probe 0 3)"
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: FAIL — `int(3*0.9)`=2 currently classifies 2/3 as "stable".

- [ ] **Step 3: Replace truncation with a rate comparison**

Compare `p/n` against the rate directly rather than truncating a count:
`stable` iff `p*100 >= n*90`, `flaky` iff `p*100 >= n*50`, else `broken`.
Integer arithmetic only (Bash 3.2, no floats). Apply the identical change in
both scripts so the pack runner and the variance report cannot diverge.

- [ ] **Step 4: Add the interval to the report**

Add a `95% CI` column computed by a small jq Clopper-Pearson helper, so a
2/3 reads `0.67 [0.09, 0.99]` and its uninformativeness is visible.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `BEHAVIORAL_EVALS=1 bash tests/test-run-eval-pack.sh < /dev/null`
Expected: PASS.

- [ ] **Step 6: Re-baseline is REQUIRED and is a separate human step**

Changing the thresholds changes labels. Do NOT auto-update the committed
baseline in this task; note in the PR that a maintainer must run
`--update-baseline` deliberately, since re-baselining also captures whatever
model the run resolved (see the design's open question).

- [ ] **Step 7: Commit**

```bash
git add tests/run-eval-pack.sh tests/run-behavioral-evals.sh tests/test-run-eval-pack.sh
git commit -m "fix: classification thresholds honour the documented rate bars"
```
