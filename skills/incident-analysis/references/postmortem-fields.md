# Postmortem — Mitigation Applied and Evidence-Link Placement

Read at POSTMORTEM Step 3 before writing the Mitigation Applied subsection or placing evidence links; the rules stay in `SKILL.md`. Moved verbatim from `SKILL.md`.

## Mitigation Applied

| Field | Value |
|-------|-------|
| Playbook ID | The `id` of the playbook that was executed |
| Playbook Name | Human-readable name from the playbook |
| Command Executed | The exact interpolated command that was run |
| Execution Time | Timestamp when EXECUTE Step 2 completed |
| Verification Status | `verified`, `failed`, or `unverified` (from VALIDATE exit path) |
| Evidence Bundle | Relative path to `docs/postmortems/evidence/<bundle-id>/` |

## Evidence links by section

| Postmortem section | Source | Link placement |
|-------------------|--------|---------------|
| Root Cause & Trigger | `chosen_hypothesis.evidence_links` | `**Links:** [label](url) · ...` after root cause statement |
| Investigation Notes — Ruled out | `ruled_out[].evidence_links` | `**Links:** [label](url)` after each hypothesis |
| Impact — Infrastructure | `service_error_inventory[].evidence_links` | Inline links on each infrastructure bullet |
| Timeline | Query URLs from Steps 2-7 | Evidence column: `[label](url)` replacing plain-text descriptions |
| Investigation Notes — Confirmed | Source code / config URLs | Inline links on file/config references |
