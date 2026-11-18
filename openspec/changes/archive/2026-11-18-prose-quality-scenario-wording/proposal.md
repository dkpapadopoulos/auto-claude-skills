# Prose-quality scenarios assert only what the skill states

## Why

Issue #414, third item (a deferred minor from the PR #400 review). Two scenarios in the `prose-quality` spec assert a reporting behaviour that `skills/authorial-judgment/SKILL.md` does not state:

- "Explicit request on procedural text gets a scope-aware pass" ends "and say which moves were withheld and why".
- "Good newsletter draft comes back unchanged" ends "the response SHALL say which edits were considered and declined".

The skill's only reporting instruction is "End with the three largest edits and why." The two behaviours were seen in the GREEN runs of #400 as emergent, and nothing tests them. A scenario that passes only when the model happens to volunteer something is not a requirement.

## What Changes

- The first scenario stops at "apply only precision about uncertainty".
- The second scenario asserts what the requirement's own body already says: the response lists the largest edits made, or says that none were.
- No requirement body changes, no scenario is added or removed, and the skill text is untouched.

The alternative, stating both behaviours in the skill, was not taken: it changes what the skill instructs and would need its own pressure test.

## Impact

- Affected spec: `prose-quality` (two scenarios in two requirements).
- Affected code: none.
