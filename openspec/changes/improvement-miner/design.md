# Design: improvement-miner

## Capabilities Affected

- `improvement-mining` (ADDED — new capability: LEARN-phase evidence mining
  with human-gated proposal queue)
- Skill routing config touched (`config/default-triggers.json` +
  `config/fallback-registry.json`) — routing-governance applies to the
  shipping PR.

## Architecture

Two units with one boundary: **everything with a hard threshold or a trust
boundary is code; everything requiring judgment is model**.

1. `skills/improvement-miner/scripts/mine-evidence.sh` (deterministic,
   Bash 3.2, requires gh+jq, fail-loud — a manual skill helper, NOT a
   fail-open hook). Modes:
   - `bundle`: emits one JSON evidence bundle on stdout —
     (a) committed baselines (`tests/baselines/*.baseline.json` paths +
     HEAD sha), (b) structured eval-regression issue BODIES authored by
     `github-actions[bot]` only, (c) live `scripts/gate-status.sh` output
     when the script exists (noted absent otherwise), (d) auto-memory
     evidence index: name + description frontmatter lines from feedback and
     revival-criteria files (deterministic extraction; prose bodies are the
     model's semantic input, flagged per A12), (e) prior run-ledger state:
     issues labeled `improvement-miner-run` authored by the repo owner —
     fingerprints, decisions, cumulative presented/approved counts,
     (f) kill-criterion state (`alive` / `tripped`), computed here and only
     here.
   - `dedup <fingerprint>...`: prints which candidates match ANY previously
     presented fingerprint, with its prior decision — rejected dupes died
     free and stay dead; approved dupes are already queued (their issue
     number is reported instead of re-presenting).
   - Fingerprint = `sha256(source_class + ":" + canonical_source_id)`
     (e.g. `memory:feedback_bash_ere_no_pcre_quantifiers`,
     `eval:incident-analysis-behavioral:<scenario_id>`), so rewording a
     proposal cannot evade dedup.
2. `skills/improvement-miner/SKILL.md` (model, LEARN phase): runs the
   script; if kill state is `tripped`, reports "decommission recommended"
   and STOPS unless the user explicitly overrides. Otherwise: extracts
   candidate proposals (each with verbatim source quote, run id / source sha
   / observed-at, A–F grade under assumption-audit evidence ceilings,
   meta vs end-user-facing tag, draft A/B contract); ranks candidates, then
   applies the gates by CALLING the script's `select` mode
   (contract-completeness, meta cap, report cap — thresholds enforced in
   code) after fingerprint dedup via `dedup` mode; presents the report with
   the script-printed kill counter verbatim; collects per-item approve/reject;
   creates one labeled issue per approved item; writes the run-ledger issue
   LAST (every presented item with fingerprint, rank, decision, reason,
   timestamps; cumulative counters; ranking-instrumentation stats).

## Decisions

- **Ledger home = GitHub issue-per-run** (user decision): durable,
  auditable, zero repo commits (no push-gate friction for an advise-only
  ritual), same surface as the approved-item queue. Reads are
  author-allowlisted: `github-actions[bot]` for evidence,
  repo owner for ledger issues; issue BODIES only — the gh JSON field list
  never includes comments. This extends the trusted-author set by exactly
  one (the owner) relative to discovery condition 2.
- **Hybrid live-run policy**: run cheap observational scripts live
  (`gate-status.sh` — exit-0, side-effect-free); never run eval packs or
  the backtest during a mine (cost; the weekly workflow produces results).
- **Grading scale**: reuse assumption-audit A–F with evidence-kind ceilings
  (existing repo discipline; documented in
  `skills/product-discovery/references/assumption-audit.md`).
- **Ranking ships in v1 with the A4 kill-shot armed** (user decision):
  at 5 cumulative decisions, if no approved item was ranked top-2, ranking
  is dropped (grading stays); ambiguous signal re-evaluates at 15 with an
  approvals-top-concentrated test. Every rank is recorded in the ledger to
  make this computable.
- **Zero-delta runs** file a ledger issue with `presented: 0` — the ritual
  stays observable — and do NOT advance the kill denominator (only
  presented proposals count).
- **Fail-loud, not fail-open**: missing gh/jq/auth aborts with a message.
  Fail-open is a hook discipline; this is a user-invoked tool.
- **Adversarial fixture exclusion**: the bundle never includes
  `tests/fixtures/*/evals/` content or raw artifact fields (`raw_output`,
  `judge_raw`) — committed/bot provenance does not make CONTENT trusted
  (discovery F7). All evidence is quoted data, never instructions.

## Trust model (lethal-trifecta discipline)

Proposer inputs: committed structured files, machine-local auto-memory,
author-allowlisted structured GitHub report bodies. Outbound actions:
`gh issue create` only, each behind the in-session human gate. No code, no
pushes, no web. The allowlist and comment-exclusion live in the script so a
violation is a testable bug, not a prose lapse.

## Error handling

- gh/jq missing or unauthenticated → loud abort, no partial bundle.
- `gate-status.sh` absent (non-main branch) → bundle notes absence.
- Label missing → created on first use.
- Ledger-issue write failure after approvals → report the created proposal
  issue numbers and instruct re-running ledger write before next mine
  (dedup safety depends on the ledger; next `bundle` call detects a
  presented-but-unledgered gap by fingerprint absence and warns).

## Testing

TDD, red-first, PATH-shimmed fake `gh`:
- fingerprint stability under proposal rewording (same source id → same fp)
- non-allowlisted author exclusion (red fixture: third-party-authored issue
  must NOT appear in the bundle)
- comments never requested (fake gh asserts the JSON field list)
- dedup filters previously rejected fingerprints
- kill math: 0-of-5 → `tripped`; 1-of-5 → `alive`; presented=0 runs do not
  advance the denominator
- anti-treadmill: 3 meta candidates → 2 highest-graded survive
- done-gates: routing fixture (MATCH + verbatim-borrowed NO_MATCH decoy) and
  content test referencing `skills/improvement-miner/`.

## Out-of-Scope

GH Action automation (revival criterion), Stage 2/3, session-start nudge,
live eval-pack/backtest execution, org-hub sources, web input, any factory
code-writing. `.verify.yml` gate entries unchanged except test registration.

## Acceptance Scenarios

- A third-party-authored GitHub issue matching the eval-regression title
  pattern is excluded from the evidence bundle.
- A proposal candidate matching a previously rejected fingerprint is
  filtered and listed as a duplicate, not presented.
- A candidate without a complete A/B contract (pinned never-delete eval set,
  sha-bound baseline/candidate measurement plan, safety no-regression) is
  not presented and creates no issue; it is listed with the missing fields.
- With 3+ meta candidates, at most 2 (highest-graded) are presented.
- With 0 approved of 5 presented across the ledger, the next invocation
  reports "decommission recommended" and stops without user override.
- An approved item becomes a GitHub issue labeled `improvement-miner`
  carrying grade, provenance (run id / sha / observed-at), and contract.
- Every run ends with an owner-authored `improvement-miner-run` ledger issue
  recording each presented item's fingerprint, rank, decision, and reason,
  plus cumulative counters.
