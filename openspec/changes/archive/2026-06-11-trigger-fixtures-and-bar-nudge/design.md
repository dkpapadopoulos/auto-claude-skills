# Design: Adversarial trigger fixtures + measurable-bar [info] nudge

## Capabilities Affected

- `skill-routing` — per-skill trigger-regex fixture coverage (data only; harness unchanged) and the PLAN-phase design-guard advisory surface.

## Architecture

**Part 1 — fixture content (no code).** `tests/test-regex-fixtures.sh` already reads every `tests/fixtures/routing/<skill>.txt`, resolves the skill's triggers from `config/default-triggers.json`, and asserts `MATCH:`/`NO_MATCH:` directives with the same lowercased `[[ =~ ]]` ERE evaluation the activation hook uses. We add six fixture files for the skills all three debate perspectives flagged as collision-prone (shared `ship|merge|release`, `review|pr`, attack-lexicon, and broad build-verb alternations): `incident-analysis`, `brainstorming`, `requesting-code-review`, `supply-chain-investigation`, `verification-before-completion`, `outcome-review` — the last two substituting the debate's `security-scanner` and `finishing-a-development-branch`, which turned out to be composition-routed with no trigger regexes. Fixture authoring surfaced three real false positives (preview→`review`, relationship→`ship`, staging→`tag`); a systematic sibling scan during quality review then found the same bug class in eleven more places (full enumeration in the delta spec), all fixed via word-boundary anchors in both registry files, each pinned by fixture regressions. As-built: 13 new fixture files, 120 assertions, 14 anchored words across 10 skill triggers + 2 hints. Fixture quality rule: every NO_MATCH must be a near-miss — a prompt containing at least one token adjacent to the skill's alternation that the regex must nonetheless reject. Scope boundary (explicit, from the debate): fixtures prove **regex fidelity** only; role-cap **displacement** remains covered by `tests/test-routing.sh` (`*_does_not_displace_*` and false-positive functions).

**Part 2 — [info] bar nudge (~8 LOC).** Inside the existing design-guard block in `hooks/skill-activation-hook.sh` (the PR #49 tolerant-heading region), after the three heading checks and only when the design file is readable: grep the body once with a numeric-threshold ERE (digits + unit/percent, `p50/p90/p95/p99`, `threshold`, comparison operators). If no hit, append one line to the DESIGN COMPLETENESS output:
`  [i]  No numeric bar found — if success is measurable (latency, %, tokens, pass-rate), state the threshold (advisory only)`.
It is informational: it never contributes to the pass/fail verdict, never produces an [X], and any grep failure leaves output unchanged (fail-open). `SKILL_EXPLAIN=1` emits a `[design-guard] bar=<0|1>` breadcrumb. The exact ERE is tuned against the design-doc corpus: of the 12 docs testable at implementation time, the 8 organically-numeric docs MUST NOT trigger the line (the debate's initial 10/14 figure used a looser pattern; 8/12 is the measured implementation value).

## Trade-offs

- An [info] line that cannot fail cannot enforce — accepted deliberately; the debate showed the norm is 71% organic and the cultural guard (eval-baseline memory) is the real enforcement. We buy visibility at zero nag cost instead of theater at ceremony cost.
- The line will appear on legitimately non-numeric designs (4/14 in the corpus). Accepted: it is one informational line, not a failure, and those authors already weighed the choice.
- Fixture files rot when triggers change — but they rot loudly (suite fails), which is their purpose; the harness is config-sourced so there is no second copy to drift.
- One accepted false-negative from the narrowing: "enable automerge on this branch" no longer fires `verification-before-completion` (the composition chain and push gate still cover real ship flows). The `[i]` bar grep also false-quiets on `[0-9]+s` tokens like "k8s" — harmless direction (suppresses an advisory).

## Dissenting views

- **Critic (C3):** the [info] line is "a no-op nudge" — the norm needs no guard at 71% organic adoption; 8 LOC + tests to nudge an existing habit fails match-scope-to-fix-size. Recorded; overruled by user decision adopting the architect's variant.
- **Critic (C1 residual):** even fixture population may be marginal given case-by-case displacement coverage exists. Mitigated by restricting to the six demonstrably collision-prone skills and the adversarial NO_MATCH rule.
- **Debate-wide correction:** the consensus "wire the harness" task was based on a false premise (glob discovery already runs it). Removed from scope; recorded so it is not re-proposed.

## Out-of-Scope

- No CI workflow for the bash test suite (separate suite-wide question; enforcement point today is the verification-before-completion chain gate).
- No required opt-out line at SHIP (C2 — dropped; revival: second active dev or ≥2 logged regrets).
- No new design-doc headings, no [X]-level bar enforcement, no LLM-judged scoring changes to skill-eval.yml.
- No fixture files for narrow-trigger skills (incident-trend-analyzer etc.) — low collision risk, rot for nothing.
- No changes to role-cap selection or displacement testing.

## Decisions

1. Adopt fixture content for the six debate-identified skills; extend to any skill where authoring or review finds a live trigger bug (final count: 13), defer the rest until a collision is observed.
2. Adopt the [info] bar nudge as content-grep, never heading-grep, never blocking (user decision 2026-06-11, architect's dissent variant).
3. Architect's reliability condition is binding: if the numeric ERE cannot cleanly split the 14-doc corpus (10 quiet / 4 flagged), drop the nudge rather than tune toward a heading requirement.

## Acceptance Scenarios

See `specs/skill-routing/spec.md` in this change.

## Implementation Notes (synced at ship time)

- Scope extended during review, by design-debate quality gates rather than drift: the planned 6 fixture files became 13 and the planned 3 anchor fixes became 14, because fixture authoring plus a systematic sibling scan kept exposing live instances of the same bug class (each empirically pre-verified before fixing). proposal.md, the delta spec, and the CHANGELOG were synced to as-built numbers before archive.
- The branch was rebased onto main mid-review (PRs #49/#50 landed concurrently); the rebase initially reverted #49's tolerant heading greps because the branch was cut pre-merge — caught and resolved by keeping tolerant greps + the [i] bar addition. Final suite green at 55/55 files.
- Corpus figure: implementation-time measurement is 8/12 numeric docs (the debate's 10/14 used a looser pattern).

## Divergences (auto-generated at ship time)

**Acceptance Scenarios (from specs/skill-routing/spec.md in this change):**
- [x] Near-miss prompt does not fire an adjacent skill — implemented as designed (120-assertion harness, all NO_MATCH lines adversarial)
- [x] Trigger drift caught before merge — implemented as designed (harness glob-discovered by run-tests.sh; "no wiring step exists" correction held)
- [~] Word-boundary anchoring — implemented with EXPANSION: planned review/ship/tag (3 words) grew to 14 words across 10 skills + 2 hints via the sibling scan; every addition followed the same pre-verify discipline
- [x] [i] bar line on no-numerics doc, silent on numeric doc, fail-open — implemented as designed (2 regression tests; corpus figure corrected 10/14 → 8/12)

**Scope changes:**
- Added: 7 fixture files beyond the debate's six (agent-team-review, systematic-debugging, receiving-code-review, executing-plans, deploy-gate, openspec-ship, batch-scripting) — driven by live bugs found, not speculation
- Removed: none
- Modified: fixture shortlist substitution (security-scanner, finishing-a-development-branch → verification-before-completion, outcome-review) — original targets are composition-routed with no trigger regexes

**Design decision changes:**
- None at mechanism level. The [i] line, anchor idiom (leading-only except mass), and fail-open posture shipped exactly as decided. Mid-flight rebase onto main (PRs #49/#50) initially reverted #49's tolerant heading greps; caught at REVIEW and resolved by layering the bar nudge onto the tolerant greps.
