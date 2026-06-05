# Incident-Analysis Rigor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two prompt-only, deterministically-testable behaviors to the `incident-analysis` skill — postmortem action-item phase typing (Detect/Prevent/Mitigate) and ASCII risk labels on destructive commands.

**Architecture:** Both additions land in reference files to respect the 1-word `SKILL.md` word-count guard. `#8` extends `references/postmortem-template.md`. `#2-lite` adds `references/command-risk.md` plus one short pointer in `SKILL.md` at the HITL gate, offset by trimming two pre-identified redundant phrases. Regression is enforced by the existing fast content tests (`test-incident-analysis-content.sh`, `test-postmortem-shape.sh`) — no new dependencies, no `claude -p` runs required.

**Tech Stack:** Markdown skill files; Bash 3.2 test harness (`tests/test-helpers.sh` → `assert_contains`, `assert_file_contains`, `_record_pass`/`_record_fail`).

**Acceptance scenarios** (from `openspec/changes/incident-analysis-rigor/specs/incident-analysis/spec.md`):
- AC-1 Every postmortem action item carries a `Type` ∈ {Detect, Prevent, Mitigate}.
- AC-2 Detection-gap actions classify as `Detect`; built-in schema path includes the field.
- AC-3 Destructive commands prefixed `RISK: HIGH — <reason>`; reversible `RISK: MEDIUM — <reason>`.
- AC-4 Read-only queries are NOT labeled.
- AC-5 The `RISK:` token is ASCII (`grep -F`-assertable, not emoji-dependent).

---

### Task 1: Action-Item Phase Typing (#8)

**Files:**
- Modify: `skills/incident-analysis/references/postmortem-template.md:18-21`
- Test: `tests/test-postmortem-shape.sh` (add assertions) and `tests/test-incident-analysis-content.sh` (add reference assertion)

- [ ] **Step 1: Write the failing test**

Append to `tests/test-postmortem-shape.sh` after the existing Action Items block (after line ~54, before Test on Timeline ordering — place near the other `SCHEMA_BLOCK` assertions). `SCHEMA_BLOCK` is already defined earlier in the file as the fenced built-in schema extracted from `postmortem-template.md`.

```bash
# Test: Action Items declare a Type field with the three phase values
assert_contains "action items: Type field present" "type" "${SCHEMA_BLOCK}"
assert_contains "action items: Detect value defined" "Detect" "${SCHEMA_BLOCK}"
assert_contains "action items: Prevent value defined" "Prevent" "${SCHEMA_BLOCK}"
assert_contains "action items: Mitigate value defined" "Mitigate" "${SCHEMA_BLOCK}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-postmortem-shape.sh`
Expected: FAIL on the four new assertions (`Detect`/`Prevent`/`Mitigate` not yet in the schema block).

- [ ] **Step 3: Write minimal implementation**

Replace `skills/incident-analysis/references/postmortem-template.md` lines 18-21:

```markdown
## 3. Action Items
Ordered by priority (P0 first). Each item MUST have a suggested owner and due date.
Items without owners should be flagged: "⚠ Owner needed".
Include: priority, action, type, current state, owner, due date, status.
**Type** classifies how the item reduces future incidents — exactly one of:
- **Detect** — improves time-to-detection for this failure class (alert, SLO, monitoring).
- **Prevent** — stops the root cause from recurring (validation, CI gate, guardrail).
- **Mitigate** — reduces blast radius or speeds recovery when it recurs (runbook, automation, capacity).
A postmortem with several Prevent items and zero Detect items signals an unaddressed detection gap.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-postmortem-shape.sh`
Expected: PASS (all assertions green).

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/references/postmortem-template.md tests/test-postmortem-shape.sh
git commit -m "feat: postmortem action-item phase typing (Detect/Prevent/Mitigate)"
```

---

### Task 2: Command-Risk Reference File (#2-lite)

**Files:**
- Create: `skills/incident-analysis/references/command-risk.md`
- Test: `tests/test-incident-analysis-content.sh` (add a new assertion block)

- [ ] **Step 1: Write the failing test**

Append to `tests/test-incident-analysis-content.sh` after the evidence-links reference assertions (the `assert_file_contains`/`assert_file_exists` helpers are defined at the top of the file):

```bash
# ---------------------------------------------------------------------------
# references/command-risk.md — destructive-command risk labels (#2-lite)
# ---------------------------------------------------------------------------
COMMAND_RISK_REF="${PROJECT_ROOT}/skills/incident-analysis/references/command-risk.md"
assert_file_exists "references/command-risk.md exists" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: ASCII RISK token" "RISK:" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: HIGH level" "RISK: HIGH" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: MEDIUM level" "RISK: MEDIUM" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: read-only exclusion rule" "[Rr]ead-only" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: emoji-not-sole-marker rule" "[Aa]SCII" "${COMMAND_RISK_REF}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: FAIL — `references/command-risk.md` does not exist yet (assert_file_exists fails, dependent asserts fail).

- [ ] **Step 3: Write minimal implementation**

Create `skills/incident-analysis/references/command-risk.md`:

```markdown
# Command Risk Labels — Destructive-Action Annotation

Applied at the HITL gate (see SKILL.md § "1. HITL Gate") before presenting any
destructive or mutating command. Read-only investigation queries are NEVER labeled —
labeling safe reads trains the reader to ignore the marker (alert fatigue; see the
`alert-hygiene` skill).

## Format

Emit one ASCII line immediately before the command:

    RISK: HIGH — <reason>      # irreversible, data-loss, or wide blast radius
    RISK: MEDIUM — <reason>    # temporary disruption or reversible

The leading token `RISK:` MUST be ASCII so it is regex- and `grep -F`-assertable. An
emoji MAY follow the reason for readability but MUST NOT be the sole marker.

## Level selection

| Level | Use for | Examples |
|-------|---------|----------|
| HIGH | Irreversible / data loss / wide blast radius | resource deletion, node drain, cluster destroy, IAM policy change |
| MEDIUM | Temporary disruption / reversible | workload restart, rollout undo, replica or resource resize |

## Examples

    RISK: HIGH — deletes the NetworkPolicy; if wrong, all checkout traffic stays blocked.
    kubectl delete networkpolicy update-checkout-from-frontend

    RISK: MEDIUM — rolling restart drops in-flight connections on this deployment only.
    kubectl rollout restart deployment/frontend
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: PASS on the six new command-risk assertions.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/references/command-risk.md tests/test-incident-analysis-content.sh
git commit -m "feat: command-risk reference for destructive-action risk labels"
```

---

### Task 3: SKILL.md HITL Pointer + Word-Guard Offset (#2-lite wiring)

**Files:**
- Modify: `skills/incident-analysis/SKILL.md:54` (add pointer), `:802` and `:808` (offset trims)
- Test: `tests/test-incident-analysis-content.sh` (pointer assertion + existing word-count guard at line ~671)

- [ ] **Step 1: Write the failing test**

Append to `tests/test-incident-analysis-content.sh` (near the other `SKILL_FILE` assertions):

```bash
# SKILL.md — HITL gate references the command-risk label (#2-lite)
assert_file_contains "SKILL.md: HITL gate points to RISK label" "RISK:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: HITL gate references command-risk ref" "command-risk" "${SKILL_FILE}"
```

The word-count guard already exists at `tests/test-incident-analysis-content.sh:671` (`[ "$word_count" -le 11500 ]`) — it will start FAILING once the pointer is added, until the offset trims are applied. That is the TDD signal for Step 3b.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: FAIL on the two new pointer assertions (`RISK:`/`command-risk` not yet in SKILL.md). Word-count guard still PASSES (11499 ≤ 11500) at this point.

- [ ] **Step 3a: Add the HITL pointer**

In `skills/incident-analysis/SKILL.md:54`, append one sentence to the end of the existing HITL-gate paragraph (after "…copilot, not an autopilot."):

```
Prefix any such command with a `RISK:` label (`references/command-risk.md`); read-only queries are never labeled.
```

- [ ] **Step 3b: Apply offsetting trims to stay ≤ 11500 words**

The pointer adds ~16 words; the guard now fails (11499 → ~11515). Apply these two semantically-neutral trims (both remove redundancy, not meaning):

`SKILL.md:802` — replace:
```
Entered after the user approves a high-confidence CLASSIFY decision at the HITL gate. This stage applies the mitigation command with a fingerprint safety check.
```
with:
```
Entered after the user approves a high-confidence CLASSIFY decision. This stage applies the mitigation command after a fingerprint recheck.
```
(removes "at the HITL gate" — redundant with "approves… CLASSIFY decision"; "with a fingerprint safety check" → "after a fingerprint recheck", redundant with Step 1 "Fingerprint Recheck".)

`SKILL.md:808` — replace:
```
Do not attempt to execute kubectl commands without kubectl installed. Present the command for the user to run externally if needed.
```
with:
```
Never run kubectl commands without kubectl installed; present the command for the user to run externally instead.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: PASS on the two pointer assertions AND the word-count guard (`SKILL.md: word count under 11,500`). If the guard still fails, confirm the count:

Run: `wc -w skills/incident-analysis/SKILL.md`
Expected: ≤ 11500. If over, trim one more redundant phrase (candidate: `SKILL.md:54` "You are a copilot, not an autopilot." → "You are a copilot, not an autopilot" is 7 words; or tighten line 802 further) and re-run.

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat: HITL gate emits RISK label for destructive commands"
```

---

### Task 4: CHANGELOG + Full Suite + OpenSpec Validation

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` accumulator)
- Verify: `tests/run-tests.sh`, `scripts/validate-active-openspec-changes.sh`

- [ ] **Step 1: Add CHANGELOG entry**

Under the existing `## [Unreleased]` header in `CHANGELOG.md`, add (do NOT promote to a versioned header — `[Unreleased]` is an accumulator):

```markdown
### Added
- `incident-analysis`: postmortem action items now carry a `Type` field (Detect/Prevent/Mitigate) to surface detection gaps.
- `incident-analysis`: destructive/mutating commands at the HITL gate are prefixed with an ASCII `RISK: HIGH|MEDIUM — <reason>` label (`references/command-risk.md`). Read-only queries are not labeled.
```

- [ ] **Step 2: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: all suites PASS, including `test-postmortem-shape.sh` and `test-incident-analysis-content.sh`.

- [ ] **Step 3: Re-validate the OpenSpec change**

Run: `bash scripts/validate-active-openspec-changes.sh`
Expected: `PASS: incident-analysis-rigor`.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for incident-analysis rigor additions"
```

---

## Self-Review

**Spec coverage:**
- AC-1 (every item typed) → Task 1 (`Include: priority, action, type, …` + value list).
- AC-2 (Detect for detection gaps; built-in schema path) → Task 1 (built-in schema is the file edited; value definitions present).
- AC-3 (HIGH/MEDIUM labels) → Task 2 (format + examples) + Task 3 (HITL pointer fires it).
- AC-4 (read-only not labeled) → Task 2 (explicit exclusion rule, tested) + Task 3 pointer text.
- AC-5 (ASCII-assertable) → Task 2 (`grep -F "RISK:"` assertion) + Task 3 pointer uses ASCII token.

**Placeholder scan:** none — every step has exact paths, full file content, and concrete commands.

**Type consistency:** field name is `type`/`Type` consistently across Task 1 template and tests; risk token is `RISK:` consistently across Task 2 reference, Task 3 pointer, and all assertions; reference filename `references/command-risk.md` consistent across Tasks 2–3 and the proposal Impact section.

**Note on the word guard (Task 3):** the offset trims are the only behavioral risk. They are semantically neutral (remove redundancy with adjacent text). Step 4 re-verifies `wc -w ≤ 11500` and gives a named fallback trim if needed.
