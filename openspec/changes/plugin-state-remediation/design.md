## Architecture

Every change is to an existing bash hook, its JSON config, or a test. Display changes are content or render-only: the composition state write, `_DISPLAY_SUPPRESS`, and every gate predicate stay byte-identical for every recorded input, which the existing display-suppression fixture pair and the real-prompt replay probe verify. Performance changes replace process forks with bash parameter expansion and a single batched jq over all LSP manifests; a fork-count ratchet over an isolated test HOME pins the count so it cannot regrow silently. The frontmatter merge gains a tier: external-marketplace entries are parsed separately and stripped of the four topology keys before the bundled and user tiers are merged over them.

## Trade-offs

- Hint prose shrinks; the procedure moves to the owning skill. The model reads the procedure only when it invokes the skill, which is the progressive-invocation shape the superpowers chain already uses. Cost if wrong: a model that would have followed a long inline hint but does not invoke the skill loses the detail. Mitigation: each hint keeps its condition and `Skill(...)` name.
- The ratchet pins the clean-tree state (line rendered) rather than the dirty one. Cost if wrong: none to users; a future change to PHASE REALITY's text moves the baseline by its byte delta, which is the behaviour a ratchet should have.
- Topology refusal is tier-based, not name-based. A user who installs an external plugin that legitimately overrides a config-owned skill's phase loses that override. Measured: no installed plugin carries any of the four keys for any name.
- The carrier stays. A retirement rule is written down instead: three consecutive months of complete pairing per the reader.

## Dissenting views

- Codex: replay agreement proves reproducibility, not correctness; low mandate compliance is not itself the defect since most mandates were wrong; the sticky-repeat experiment has no eligible observations and must not be loosened to create some. Accepted; none of these is changed here.
- Debate critic: a retirement program in an incident-paid repo fails silently because the gotchas guard fail-open classes. Accepted: the only thing retired here is a premise comment, with a reader that makes the carrier's own retirement decidable later.
- Debate architect: the brainstorming verb deletion saves about 70 tokens per prompt against a block of 1,200 to 1,500 and is not display-only. Accepted: not in this change.

## Decisions

- One OpenSpec change, six PRs, each independently revertable; the change archives when the last merges.
- Fork-count ratchet rather than a wall-clock assertion: time is machine-dependent, the count is not.
- `_INJECTION_BASELINE` moves twice (re-pin, then the cut), each in the commit that moves it.
- #295 is not touched: the predicate has no harness-observed source to switch to; its measurement is labelling the #343 corpus, which only the owner can do.
- #249 is left as a recurrence watch: both halves are accounted for by #270 and #291 and the capture log shows 25 of 25 denies matched by replay.
