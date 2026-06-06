# Proposal: Incident-Analysis Rigor — Action-Item Typing + Destructive-Command Risk Labels

## Why

A review of the Gemini CLI SRE extension (`github.com/gemini-cli-extensions/sre`) and its companion real-investigation corpus (`github.com/palladius/about-sre-extension`, 12 documented incidents) was run through a three-perspective design debate (architect / critic / pragmatist) plus an independent Codex repo-grounded fact-check. Eight candidate practices were triaged against our existing `incident-analysis` skill. Most overlapped with what we already ship (tiered tool detection, evidence-only attribution, confidence-gated playbooks, postmortem permalinks, typed evidence links, dated evidence bundles). Two represent genuine, low-cost gaps that change investigation **outcomes**, not presentation:

1. **Postmortem action items have no phase classification.** `references/postmortem-template.md` mandates priority/action/current-state/owner/due/status but no `Detect | Prevent | Mitigate` tag. Without it, the recurring failure mode — a postmortem that produces several "Prevent" items and zero "Detect" items, so the bug gets fixed but MTTD never improves — is invisible. Codex independently confirmed the template fields lack this tag.

2. **Destructive commands are gated but unlabeled.** The skill already captures pre-execution evidence before destructive mitigations (`requires_pre_execution_evidence`, `destructive_action` in playbooks) and HITL-gates all mutations. But the command presented to the user carries no standardized risk label. The real SRE investigations showed that an explicit per-command risk annotation + HITL is what actually carried the safety weight during direct `kubectl delete`/`patch`. Codex independently confirmed the playbooks expose `destructive_action`/`requires_pre_execution_evidence` but surface no user-facing risk label.

The debate **rejected** the other six candidates: statistical/ML anomaly detection (sklearn dependency + nondeterminism vs our deterministic threshold signals, zero logged pain — the biggest trap), `safe_gcloud`/`safe_kubectl` SA-impersonation wrappers (infra ceremony, not load-bearing even in the source repo's own investigations), per-skill `EVAL.md` (our `behavioral-evaluation` runner is strictly more rigorous), numbered "Exhibit" labels + dated investigation folders (redundant and regressive against our existing typed `evidence-links.md` + dated evidence bundles), Unicode sparklines (deferred — value is unmeasured, survivorship bias from a vendor demo repo, would add the first maintained executable), and matplotlib postmortem graphs (terminal-first harness can't render inline; never-fabricate/UTC rules already enforced).

## What Changes

Two prompt-only behavioral additions, both landing in reference files (the 979-line `SKILL.md` has ~1 word of headroom against its test guard, so net-new prose MUST avoid SKILL.md proper):

- **A — Action-item phase typing (#8):** `references/postmortem-template.md` Action Items section gains a mandatory `Type` field with values `Detect | Prevent | Mitigate`. Each action item MUST be tagged. Output is ASCII-assertable by the behavioral runner.
- **B — Destructive-command risk label (#2-lite):** at the HITL gate, before presenting any destructive/mutating command, the agent MUST prefix it with a single-line ASCII risk label: `RISK: HIGH — <reason>` or `RISK: MEDIUM — <reason>`. Scoped to destructive/mutating commands only (NOT read-only investigation queries — a label on every read-only query is alert-fatigue, which our own `alert-hygiene` skill warns against). ASCII token `RISK:` (not a bare emoji) because Unicode greps have previously broken the behavioral runner on macOS. Lives in a reference file with a single pointer line added to SKILL.md, offset by an equivalent trim so the word-count guard does not trip.

## Capabilities

### Modified
- **`incident-analysis`** — two ADDED requirements: "Action-Item Phase Classification" (POSTMORTEM stage) and "Per-Command Risk Label for Destructive Actions" (EXECUTE/HITL stage). No existing requirement text is modified; both are net-new ADDED requirements (avoids MODIFIED exact-match fragility).

## Impact

**Files modified:**
- `skills/incident-analysis/references/postmortem-template.md` — Action Items section gains the `Type` column + value definitions (uncapped reference file)
- `skills/incident-analysis/references/postmortem-template.md` — both the built-in schema and project-template paths reference the new field
- `skills/incident-analysis/SKILL.md` — one pointer line for the destructive-command risk label, offset by an equivalent trim (net word count MUST remain ≤ guard)
- A reference file (new `references/command-risk.md` or an append to `references/query-patterns.md`) — the risk-label format + the destructive-only scoping rule
- `tests/test-incident-analysis-content.sh` (or equivalent content test) — regex assertions for the `Type` column and the `RISK:` label format
- Behavioral-evaluation assertion(s) — `tool_call`/regex assertion that a destructive recommendation emits a `RISK:` line and that postmortem action items carry a `Type`
- `CHANGELOG.md` — `[Unreleased]` accumulator entry

**Dependencies:**
- None. Bash 3.2 + jq-optional unchanged. No new runtime dependencies, no new plugins.

## Out of Scope

- Statistical/ML anomaly detection (sklearn) — rejected; revival trigger: a measured threshold false-negative/false-positive on a real incident.
- `safe_gcloud`/`safe_kubectl` SA-impersonation wrappers — rejected; revival trigger: a user running investigations against prod with write-capable creds wanting enforced read-only.
- Numbered "Exhibit" evidence labels + dated investigation folder convention — rejected as redundant/regressive vs existing typed `evidence-links.md` + dated evidence bundles.
- Unicode sparklines — deferred; revival trigger: ≥2 real postmortem reviews surface "the numbers didn't convey the shape." If built: pure Bash/awk, no Python, `grep -F`-safe.
- matplotlib postmortem graph generation — out of scope for a terminal-first harness.
- Per-skill `EVAL.md` / LLM-as-judge — rejected; `behavioral-evaluation` runner supersedes it.
- A 4-level risk taxonomy on **every** command (incl. read-only) — explicitly out of scope; scoped to destructive/mutating commands only to avoid alert-fatigue.
