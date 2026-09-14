# Kickoff prompt for the next session

Paste the block below into a new Claude Code session.

---

```text
Implement the four approved composition contracts in auto-claude-skills. This
continues finished planning work; it is not a request to re-open the audit or
re-derive the design.

WORKSPACE
Work in this existing worktree:
  /Users/damian/IdeaProjects/auto-claude-skills/.claude/worktrees/acs-composition-fixes
Branch `fix/composition-defects`, tip `afd186b`, branched from `main` at `f0ccf9c`.
Verify that against git before acting.

A separate audit worktree is at
  /Users/damian/IdeaProjects/auto-claude-skills/.claude/worktrees/sdlc-composition-audit
on `codex/sdlc-composition-audit`, tip `d831b7b`, 29 commits UNMERGED. Read it for
evidence. Do NOT merge it — its publication is a separate decision, and keeping it out
keeps this production change independently reviewable.

READ FIRST, in this order
  openspec/changes/composition-contract-fixes/proposal.md
  openspec/changes/composition-contract-fixes/design.md          <- the four contracts
  openspec/changes/composition-contract-fixes/specs/skill-routing/spec.md
  tests/probes/ACCEPTANCE.md                                      <- how a reviewer checks them
  tests/probes/README.md                                          <- what the probes are and are NOT
  tests/probes/native-contracts/TESTS-TODO.md                     <- the first task

Then, from the audit worktree, as needed:
  docs/research/2026-09-11-sdlc-composition/adoption-map.md
  docs/research/2026-09-11-sdlc-composition/fix-plan-acs-defects.md   (revision 2)

WHAT IS ALREADY SETTLED — do not re-litigate
- The four contracts C1-C4 in design.md are approved, including the two dissenting
  views recorded there as rejected.
- The probe package is ported with provenance to audit commit 8c027b9. Root
  resolution was rewritten to walk up by marker; do not reintroduce parent-index
  counting.
- `tests/test-routing-probe-regression.sh` is wired into the suite and red-controlled.
  Full suite at the port: 136 files, 136 passed.
- Five routing cases are recorded VIOLATED in tests/probes/intent-routing/baseline.json.
  Those are the open defects. Fixing them is the work; the gate reports improvements.

SEQUENCE
1. Port the conformance fixtures and write its instrument tests, per
   tests/probes/native-contracts/TESTS-TODO.md. Six cases, each fixture EXCERPTED FROM
   A RETAINED REAL TRACE on the audit branch — none hand-written — and the provider
   stubbed so no test can launch a paid run. This is a bounded prerequisite, not
   another instrument audit.
2. Build the consultation-versus-development discrimination. C2 and C3 share this
   mechanism; it is the load-bearing piece.
3. Implement C1 routing and the C2/C3 selection and composition changes as SEPARABLE,
   individually reviewed increments.
4. C4 last, after its input-evidence contract is written down.

HOW EACH FIX IS ACCEPTED
Behaviourally, per the matrix in tests/probes/ACCEPTANCE.md, with HELD-OUT
paraphrases — the thirteen prompts in tests/probes/intent-routing/cases.json are
development data now, because you will be looking at them while you work.

Validate both layers: hook SELECTION (deterministic probe) and actual model DISPATCH
(native cases). They are different mechanisms — the measured second-opinion prompt was
not routed to panel, yet the model invoked panel anyway.

Include POSITIVE DEVELOPMENT CONTROLS, not only consultation negatives: continuation,
cancellation, mixed intent, presets, overrides, unavailable skills, fallback registry.
The likeliest regression is suppressing legitimate development routing during a
consultation detour, and nothing has measured that path.

CONSTRAINTS THAT WILL BITE
- The probes are frozen baselines and non-regression detectors. Do NOT promote their
  skill-name assertions into acceptance gates: both assert `expect_absent: panel`, so
  a CORRECT one-participant consultation would fail them.
- Do NOT wire live model calls into the normal test suite. conformance.py is paid and
  non-deterministic; keep it explicitly invoked with a budget and retained evidence.
- routing-governance denies any push touching skills/, config/ or hooks/ without a
  clean project-verification verdict covering HEAD, and the applicable push-gate path
  also needs REVIEW evidence. Run these; do not discover them at push time.
- .verify.yml is the whole suite — one unrelated red test blocks every routing push.
- config/fallback-registry.json must stay in sync with config/default-triggers.json;
  phase-contract tests reject null/empty phases.
- Hook edits are Bash 3.2, and `bash -n` is not sufficient: the agent shell is zsh, so
  exercise hook changes under real bash.
- A new skill needs a routing fixture with a verbatim-borrowed NO_MATCH decoy AND a
  tests/*.sh referencing skills/<name>/, or CI fails.

DO NOT
- Do not fix C1 by changing triggers alone. Hook selection and model choice are
  separate mechanisms; a roster whose only consultation-shaped option is the panel
  will keep attracting the model.
- Do not fix C3 by suppressing the chain. Preserve an active workflow; avoid starting
  an unrelated one. A mixed request keeps its chain.
- Do not relax disable-model-invocation for C4. Gate on input evidence instead.
- Do not claim any upstream method improves engineering outcomes. The audit measured
  one and found no detectable difference; every other contribution row is a named
  hypothesis with no outcome evidence.

USE CODEX
Adversarially, on the two things it was good at during the audit: reviewing the
routing change before you run the suite (trigger regexes are where this repo's history
shows enumeration going stale), and critiquing the C4 evidence contract. Do not use it
to write regexes; use it to attack them. It is reachable via `codex exec --sandbox
read-only`, not via the plugin's companion script.

Begin by verifying the branch state, reading the documents above, then executing step 1.
```
