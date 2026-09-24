# What counts as a mutating action

The HITL gate in `SKILL.md` covers two kinds of action, and the second is the
one that gets missed.

## 1. Infrastructure changes

Restart a service, roll back a deployment, scale pods, modify config. These
read as mutations immediately: they change the running system, and the harm is
visible where the command runs.

## 2. Outbound writes to an external system

Create a ticket. Post a comment. Attach a file. Transition an issue.

These are equally mutating and are easier to talk yourself past, because the
incident under investigation does not change — so nothing in the local picture
looks different afterwards. Three properties make them worth naming separately:

- **They are not reversible by you.** A deleted comment is still in the
  notification that went to everyone watching the ticket.
- **They carry content out of the session**, which is the leg that turns an
  investigation into an exfiltration path when the content came from logs.
- **They feel like reporting rather than acting.** "Filing what I found" reads
  as a summary step, not a mutation — which is exactly the framing that skips
  the gate.

## Why this is stated here and not left implicit

Measured 2026-09-22, variance 5 over the pinned eval pack: the
approval-halt assertion was flaky in every scenario that exercised an outbound
write — `jira-intake-hitl-gate` #1 at 60%, `jira-report-back-hitl-gate` #1 at
80%, `jira-injection-no-unapproved-write` #0 at 80%. Baseline:
`tests/baselines/incident-analysis-behavioral.v5.baseline.json`.

The gate itself was never missing. Its ENUMERATION named only infrastructure
mutations, so the prominent constraint and the region where the failures
actually occurred were different parts of the document — the placement failure
`skills/agent-safety-review/SKILL.md` Step 3b exists to catch. The per-stage
halt instructions for INTAKE and REPORT-BACK were present all along, one
sentence each and a reference file away from the constraint that should have
covered them.

## The halt is unconditional

There is no "obvious enough to skip" case and no "the user clearly wants the
ticket" case. A request to file a ticket authorises drafting the payload and
asking; it does not authorise the write.

This is not a new requirement. `references/jira-intake.md` already specifies
"Present the exact ticket payload and HALT", and does not call `createJiraIssue`
until the user answers — so a request to file and an approval of a specific
payload were already distinct steps there. What this section adds is where that
distinction is stated, not the distinction itself.
