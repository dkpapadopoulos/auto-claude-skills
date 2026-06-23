# Proposal: Jira-bracketed incident-analysis flow

## Why

Incident-analysis today is a single linear flow that terminates by writing a
postmortem `.md` to disk. There is no fast hand-off to the engineering org at
the *start* of an incident, and no structured loop-back of the investigation
outcome to a tracking ticket at the *end*. Responders manually create Jira
tickets and manually paste findings, which delays informing the relevant
tribe/squad and loses the connection between the ticket and the investigation
output.

This change brackets the existing investigation with two opt-in Jira stages so
that (1) the relevant group is informed fast with initial details + early
recommendations, and (2) the investigation outcome is summarized back onto the
same ticket — without the plugin ever auto-committing investigation artifacts
to any repository.

## What Changes

- **New opt-in `INTAKE` stage** at the front of the flow. Gathers initial
  incident details (symptom, service, environment, time window, severity), runs
  a quick first-pass triage to draft a short "recommended areas to investigate"
  list, asks which Jira project/board to file against (via
  `getVisibleJiraProjects`, no hardcoded default), confirms issue type, then
  **HALTs and presents the exact ticket payload for explicit approval** before
  `createJiraIssue`. The returned ticket key is held in session state. INTAKE
  can instead **adopt** a ticket key the user supplies, skipping creation —
  covering the deferred / different-responder hand-off case.
- **New opt-in `REPORT-BACK` stage** after POSTMORTEM. Writes the postmortem
  `.md` to a **neutral, non-git-tracked path** (session scratchpad or a
  user-configured incident-output dir) by default — never CWD's
  `docs/postmortems/` unless the user named a host location. Builds a concise
  comment (**Summary** + **Proposed next steps**, carried from postmortem action
  items), tells the user the local report path to attach manually (or links a
  user-specified host location), then **HALTs for approval** before
  `addCommentToJiraIssue`.
- **No true file attachment.** The Atlassian MCP exposes no attachment tool;
  the report is delivered as an inline summary comment plus a manual-attach
  instruction or a user-specified repo link.
- **Word-budget offset.** `SKILL.md` is at the 11,500-word test guard, so the
  thin stage pointers added to `SKILL.md` are offset by extracting existing
  prose into `references/`. New stage mechanics live in
  `references/jira-intake.md` and `references/jira-report-back.md`.
- **Lethal-trifecta mitigation.** The flow now combines private data (logs) with
  an outbound action (Jira writes). Both writes are HITL-gated with the exact
  payload shown; log content is summarized/redacted, never echoed verbatim, into
  ticket text. A failing-first injection safety case is added to the
  behavioral-evaluation pack before the Jira-writing behavior is implemented.

The investigation logic itself (MITIGATE → CLASSIFY → INVESTIGATE → EXECUTE →
VALIDATE → POSTMORTEM) is unchanged.

## Capabilities

### Modified
- **`incident-analysis`** — gains an opt-in `INTAKE` stage (create-or-adopt a
  Jira ticket with initial details + early recommendations, HITL-gated) and an
  opt-in `REPORT-BACK` stage (neutral-path report write + HITL-gated summary
  comment). The Jira-writing path inherits the existing redaction discipline,
  and the new behavior is covered by an append-only injection safety case in the
  behavioral pack.

## Impact

**Files modified:**
- `skills/incident-analysis/SKILL.md` — thin INTAKE / REPORT-BACK stage pointers
  in Stage Flow + stage headers; offsetting prose extracted to references.
- `tests/fixtures/incident-analysis/evals/behavioral.json` — injection safety
  case + INTAKE/REPORT-BACK behavior cases.
- `openspec/specs/incident-analysis/spec.md` — synced ADDED requirements at ship.

**Files created:**
- `skills/incident-analysis/references/jira-intake.md`
- `skills/incident-analysis/references/jira-report-back.md`

**Out of scope:** changes to MITIGATE→VALIDATE logic; new routing triggers
(symptom triggers already route the skill); auto-commit/push of reports;
real Jira file attachment.
