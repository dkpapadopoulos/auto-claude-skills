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

## Implementation Notes (synced at ship time)

Shipped as PRs #347, #348, #349, #350, #351 and #352, all merged 2026-10-12 (v3.95.4 to v3.95.8). Deviations from the upfront design, each recorded in its PR body:

- The hint ceiling is 480 bytes, not the 240 first drafted: the spec-driven PERSIST DESIGN hint carries the three-file layout the model must reproduce. Replay over 200 real prompts: routing block 1,027,896 to 864,205 bytes (-15.9%), zero composition-state diffs. `_INJECTION_BASELINE` moved 24,855 to 24,988 (re-pin, clean-tree state) and then to 21,917 (the cut).
- The gate-consequence suffix consults the branch ledger once per render and is omitted when the ledger already records the Skill on this branch; without that the note was false after a cross-session invocation.
- The topology strip is applied in the Step 6 merge for config-owned names with no local-tier entry, not to the whole external map, so an external skill under a non-config name keeps its own topology, and `skill-rules.json` triggers for config-owned names still reach them through the external tier (a self-found gap after the first cut). `INVOKE_MAP` stays last-wins and is recorded as a residual, not fixed.
- The fork ratchet is 33 (30 after PR #348, plus one frontmatter parse and one merge per build for the tier split).
- The pairing reader's exit discipline widened in review: exit 3 also when no compaction line is recognised, exit 1 also on an unrecognised line, a carrier recovery closes the oldest open compaction, pending and stray recoveries are listed. The retirement rule became two-part (carrier=0 AND exit 0 with zero pending) because `carrier=` is a lower bound that can also overcount.
- Four reviewer items were ruled out of scope and left as-is: a `.codex` rollout path appearing once as a compaction path, the carrier not logging its own path, SessionStart consuming the marker only when its token resolves, and paths with spaces truncating identically in both producers.
