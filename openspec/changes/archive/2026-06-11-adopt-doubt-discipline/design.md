# Design: Adopt Doubt Discipline

## Architecture

All four review-side rules graft into existing sections of `skills/agent-team-review/SKILL.md` rather than forming a new skill:

- **Claim withholding** → new rule block in `### 2. Spawn Reviewers`: reviewers receive the artifact (diff) and contract (design doc / plan / spec) only. The implementer's self-summary, claims of correctness, or completion notes MUST NOT be included in reviewer prompts.
- **Doubt-theater red flag** → new `## Red Flags` section: if across 2+ review rounds reviewers surfaced substantive findings and zero were classified actionable, the lead is validating, not reviewing — stop and surface the dismissal pattern to the user. This is the checkable form of the bot-review-asymptote rule.
- **Cross-model offer** → addition to `### 5. Verdict Routing`: when the verdict is `clean` or `suggestions_only` and the diff contains external-fact claims (library surfaces, tool names, version availability), the lead MUST offer a Codex second opinion before proceeding to SHIP. Skipping on user decline is fine; silent skipping is not. Cross-model invocation MUST be read-only/sandboxed because the diff itself may contain injected instructions.
- **Sensitive-path override** → new row in `## Sizing Rule`: changes touching auth, secrets, permissions, hooks, or CI config spawn the reviewer team regardless of file count (at minimum security-reviewer + adversarial-reviewer).

The description rule grafts into `skills/skill-scaffold/SKILL.md` Step 2 (frontmatter skeleton) and Step 3 (routing entry snippet) as a single authoring rule.

## Trade-offs

- **Skill text vs hook enforcement.** These are prompt-level disciplines, not hard gates. Enforcing claim-withholding via a hook would require parsing reviewer spawn prompts — disproportionate to the risk. Content tests pin the text; the push gate remains the hard boundary.
- **Cross-model offer adds a turn** to clean reviews that contain external-fact claims. Accepted: PR #34 showed 17 Claude reviews missing what one Codex pass caught.
- **Sensitive-path override may spawn teams for tiny changes** (e.g., 1-line hook edit). Accepted deliberately: hooks and auth are where 1-line changes do the most damage.

## Dissenting views

- Source repo bounds its doubt loop at 3 cycles; we already cap review iterations at 2-3 via the bot-review-asymptote rule and `max_iterations` role-gating, so no new cycle cap is added — the doubt-theater flag covers the failure mode the cap exists for.
- Considered porting `doubt-driven-development` as a standalone skill: rejected. It would overlap agent-team-review's REVIEW slot and add a routing entry for behavior expressible in four short rule blocks (match scope to fix size).

## Decisions

1. Graft into existing skills; no new skill, no routing changes.
2. Capability homes: `adversarial-review` (review rules), `skill-routing` (description rule). No new capability.
3. ADDED requirements only — no MODIFIED (canonical-body match risk; per project convention prefer ADDED with new names).
4. Out of scope: interview-me mechanics (deferred, lean-injection precedent), three-tier security boundaries (deferred to agent-team-review security specialist), observability-instrumentation skill (deferred with revival trigger), sdd-cache, simplify-ignore, personas, anatomy CI lint (all skipped — see triage in session memory).

## Implementation Notes (synced at ship time)

- Built as specified; all 5 ADDED requirements implemented and pinned by content tests (18 governance + 4 scaffold assertions, full suite 54/54).
- Review (verdict "with fixes") added three consistency edits beyond the upfront design: the stale "5+ files" statements in agent-team-review's Overview and Integration sections were qualified to acknowledge the sensitive-path override, and the verdict-table cross-model reference was scoped "(§6, when applicable)".
- Cross-model second opinion was offered per the new rule but the Codex provider hit a session limit; recorded in the plan rather than silently skipped. External-fact claims were verified directly via gh api during triage.
