# Design: adopt-review-independence

Outcome of a four-voice design debate (architect / critic / pragmatist, plus a
cross-family Codex run in the preceding round). This file records the
architecture, the dissents, and — because several were load-bearing — the
measurements that decided each rejection.

## Architecture

Three capture mechanisms are available for an external practice, per
`adopt-addy-mechanics/design.md:9-13`:

1. **Graft into an owned skill** — prose in a `SKILL.md` we own; zero
   routing/token cost, because it loads only when the skill runs.
2. **Depend on the external plugin** — rejected there, and rejected again here.
3. **Hook-injected phase directive** — costs UserPromptSubmit tokens on every
   prompt in the phase; the eval-gated category.

**This change uses mechanism 1 exclusively.** That is the whole design. Both
grafts are prose in `agent-team-review/SKILL.md`, so nothing injects at prompt
time, the lean-injection bar has nothing to bite, and no eval is owed.

Sequencing follows the same precedent's rule — *rank by edges created, not
capabilities added*. PR 2 has a **negative** edge count: it deletes a
hand-maintained README↔`skills/` edge (already broken at 18 vs 23) and replaces
a hardcoded constant with a derived baseline.

## Trade-offs

- **Presence, not quality.** A content test greps for the paragraphs; an empty
  or badly-worded rule would pass. This is the repo's deliberate deterministic
  bar (same as `test-skill-anatomy.sh`), with quality left to human review.
- **do-not-flag is deliberately partial.** Only `pre-existing` and `tool-owned`
  ship. The other four categories from the source are already covered by
  `SKILL.md:210`, and `speculative` as worded would drop exactly the structural
  security/governance findings that `:97` and `:213` exist to protect. Shipping
  the full six-category list would reopen a hole two review rounds closed.
- **Adding prose to a 5,563-word file referenced by six test files** (one in
  CI) is safe; adding prose that contradicts §4a is the real risk. The wording
  must not introduce a competing filter alongside the evidence rule.

## Dissenting views

- **Architect** (dissent, not adopted): wanted a composition-only
  `second-opinion` skill plus a `codex` entry in the plugin roster and a
  `_plugin_installed` arm, arguing `:192`'s policy is decorative. Refuted: the
  policy has a recorded successful invocation. Its supporting observations were
  correct and are preserved above — `_plugin_installed` genuinely cannot
  express `when: installed` for a third-party plugin.
- **Pragmatist** (partly adopted): measured one new owned skill at 15 files /
  593 insertions against commit `374761b`, and argued the only tranche avoiding
  `skills|config|hooks` should go first. Adopted for PR 2. Its own correction —
  that `when` being inert makes any *conditional* hint a hook change, not a
  config edit — is recorded in the proposal.
- **Critic** (largely adopted): produced the two surviving items and refuted the
  premise both other positions shared. Also withdrew its own earlier IMPLEMENT
  hint under the same bar it applied to everyone else.
- **Unresolved, medium confidence:** whether `pre-existing` belongs in the
  do-not-flag list or as a diff-scope line in the reviewer spawn templates.
  Shipping it in the list; revisit if reviewers start missing genuine
  regressions in untouched code.

## Decisions & rejected alternatives

Every rejection is listed with its measurement in `proposal.md`. Summarised:

- **Rejected:** hint bundle (measured-negative prior, four-site bar);
  `core-skills` dependency (two independent implementation defects, no version
  field, standing precedent); `second-opinion` skill in both forms (premise
  refuted, trifecta 3/3, widens third-party egress past a guard that
  structurally cannot see Agent dispatches); "never substitute" rule (source
  self-contradiction, model-agnostic paper, violates announce-don't-block);
  CLAUDE.md migration (benefit withdrawn, destination capacity-bound, authority
  demotion); red-flags checklist as vendored prose.
- **Rejected, revivable:** `research` mechanics into `agent-team-execution`
  (durable per-agent output for cross-session resume is real, but that file
  forbids file-based status flow at `SKILL.md:89`, so it needs a deliberate
  framing pass — revive with a fan-out change). Knowledge facts for the
  mechanical repo conventions (`git add <paths>`, `-D` after squash-merge,
  `lsof -ti` over `pkill -f`) — revive when the index-size test lands, since
  they and the CLAUDE.md migration spend the same 8,192-byte budget.
- **Confirmed skip:** vendoring; the task store and status lifecycle; the
  design-handoff bridge; squash-to-main without PRs; manual releases.

## Method note, recorded against this change

The Codex round of this analysis was **confounded**: its prompt demanded "at
least two recommendations you would NOT do", and the same-family control run
carried no such instruction. The sharper critique was then attributed to model
family. The findings themselves were independently re-verified and stand; the
attribution does not. This is the failure mode `agent-team-review:105` forbids,
committed while assessing review discipline — recorded here so the next
cross-model comparison controls the instruction, not just the model.
