# Design: Review Finding Evidence Floor

## Architecture

Prose-only changes to the `agent-team-review` SKILL.md (instructions a model follows during parallel review) plus grep regression assertions. No executable/runtime changes.

- **FINDING format** gains `Confidence: high|medium|low` and `Evidence:` (observable failure path / reproduction). Reviewer spawn templates instruct reviewers to emit both fields.
- **Lead Synthesis severity floor** runs between dedupe and report: drop unmapped `quality`/`spec` suggestions; demote evidence-less `quality`/`spec` blockers. Dropped findings are reported, not discarded.
- **Category carve-out:** `security`/`governance` exempt from both drop and demote — structural blockers (removing/weakening a safety constraint) need no PoC.

## Dependencies

None.

## Decisions & Trade-offs

- **Chosen: cheap prompt-only controls.** Rejected: multi-agent adversarial-refute gate (revival trigger: a known-nit/known-real fixture shows the cheap controls don't tame nit-rate) and `agent-team-review`→`Workflow`-script migration (revival trigger: a downstream consumer needs schema-validated structured findings). Provenance: design-debate (architect/critic/pragmatist) + Codex stress-test, which WEAKENED but did not break the critic's two objections and sharpened two constraints now baked in (concrete-disconfirmable evidence; dropped-finding visibility).
- **Evidence, not confidence, is the discriminator.** Self-rated confidence is the self-preferential-bias signal the design avoids; `Confidence` is therefore advisory-only.
- **Accept warning accumulation for security/governance.** Better to surface a security warning twice than suppress one real risk; mitigated by doubt-theater detection + the visibility section.

## Implementation Notes (synced at ship time)

Built as designed. Three review rounds applied consistency fixes (security/governance demote symmetry, "permissions" trigger, Confidence advisory note); rounds 2–3 corrected gaps introduced by earlier rounds' own fixes (the bot-review asymptote).
