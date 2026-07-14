# Design: gate-gh-merge-and-compound-push

## Architecture

Detection layer (`hooks/lib/git-command.sh`, Bash 3.2, no side effects,
fail-open = "not a match"):

1. `_gc_segment_git_sub <segment>` — extracted from the existing
   `command_invokes_git_write` token walk: strips `env`/`VAR=` prefixes,
   matches `git|*/git`, skips global flags (`-C -c --git-dir --work-tree
   --namespace` + value), echoes the subcommand. `command_invokes_git_write`
   is rewritten on top of it with byte-identical semantics (existing
   `tests/test-push-gate-detection.sh` pins this).
2. `command_invokes_gh_merge <cmd>` — per segment: first real token
   `gh|*/gh`; walk tokens skipping value-taking flags (`-R --repo
   --hostname`) and other `-*`; first two non-flag words `pr merge` → match.
   First non-flag word `api` → match if the segment contains a REST merge
   path (`pulls/…/merge`) or `mergePullRequest` (GraphQL). Flag order and
   `--auto` are irrelevant by construction.
3. `command_git_mutate_before_push <cmd>` — iterate segments in order; if a
   segment's git subcommand is in the mutating set (`commit merge cherry-pick
   rebase revert am`) and a LATER segment is `git push` → match.

Guard wiring (`hooks/openspec-guard.sh`):

- Pre-filter: `*git*|*gh*` (perf-only; precision lives in the parser, cost
  bounded by the existing 4096-char cap).
- Fast-path proceeds when git-write OR gh-merge. Substring fallback (no lib /
  oversized command) adds `"gh pr merge"`, `mergePullRequest`, `pulls/` +
  `/merge` literals — fail-closed, mirroring the push fallback.
- `_gc_is_outbound = push OR gh_merge` gates the deny body; `_GATE_ACTION`
  ("pushing this branch" / "merging this PR") parameterizes messages.
- Compound deny sits FIRST inside the body (after `_PUSHGATE_SKIP`): push AND
  mutate-before-push → deny with "run the push as a separate command, after
  verification covers the new commit". Unconditional — evidence checks can't
  save it because the evidence describes pre-exec HEAD by definition.
- Composition REVIEW/VERIFY checks, verify-hardening, and the global
  fail-closed gate apply to both actions. Routing-governance keeps its
  `push`-only guard: its `origin/main...HEAD` diff describes the LOCAL branch,
  which for `gh pr merge <other>` is unrelated — an unresolvable base is the
  documented fail-open condition, so extending it would be theater.
- SHIP advisories (commit|push) unchanged.

## Trade-offs

- **Proxy evidence for gh-merge:** the gate reads the current session/branch
  ledger, not the merged PR's branch. Chosen over (a) resolving the PR's head
  branch via `gh api` inside a PreToolUse hook (network + latency + auth in a
  50ms-budget hook: no) and (b) not gating at all (audit F2). False-block
  remedy is the intentional human escape hatch; false-allow backstop is
  GitHub branch protection (documented).
- **Mutating set minimal:** `pull` excluded (common legit sync; pushes mostly
  already-remote content), `reset` excluded (plain push after reset generally
  needs force anyway). Deny-bias only where evidence is provably stale.
- **`gh pr create` ungated:** creation starts review; gating it would block
  the normal PR workflow this plugin itself drives. Pinned by regression.

## Residual limits (documented, accepted)

- Grouped forms are COVERED: leading `(`/`{` tokens are unwrapped AND trailing
  `)`/`}` closers are stripped from extracted words in both token walks, so
  `(git push)`, `(cd sub && git push)`, `{ git commit; git push; }`,
  `(git commit) && git push`, and `(gh pr merge)` are all detected. Two review
  rounds were needed: governance caught the leading-paren evasion; code review
  caught that the first fix left BARE forms open (the closer glues onto the
  final token — `push)` ≠ `push`) while docs and an args-carrying test claimed
  completeness. Both fixed red-first; guard-level bare-paren deny pinned.
- `gh api …/pulls/N/merge` WITHOUT `PUT` is the merge-STATUS read and is
  deliberately not gated (over-gating reads breeds evasion — measured live
  this session); PUT forms and GraphQL `mergePullRequest` are gated.
- Inherent string-detection ceiling (pre-existing, unchanged): `bash -c 'git
  push'`, `eval`, `xargs`, script files (`./push.sh`, Makefile targets), and
  curl-based GraphQL evade shell-string detection. GitHub branch protection is
  the per-PR backstop; the gate is a drift guardrail, not an adversarial
  boundary.

## Dissenting views

- Codex sparring (2026-07-14 audit) wanted broad `gh api` coverage; conceded
  "complete coverage is unrealistic with shell strings; branch protection
  remains the real backstop". Adopted: common REST/GraphQL forms only,
  backstop documented.
- An alternative for compound push — re-running the evidence checks
  post-mutation — is impossible in a PreToolUse hook (single pre-exec
  evaluation); splitting the command is the only sound remedy.

## Decisions

1. Same evidence bar for merge as for push (REVIEW + VERIFY); no new
   milestone kind.
2. Compound deny is unconditional (not evidence-dependent) but honors the
   human-only bypass and fail-open infra guards.
3. Red-first TDD; detector unit tests + guard behavior tests + full suite.
4. Trifecta: outbound_action coverage EXPANDS the gate (more actions gated),
   no new data legs; no agent-safety-review required.

## Implementation Notes (synced at ship time)

- Built as designed, plus two review-driven hardening rounds beyond the
  original scope (see Residual limits): grouped-form unwrapping (governance
  finding) completed with trailing-closer stripping (code-review finding —
  the first fix left bare wrapped forms open while its test stayed green),
  PUT-only gating of the REST merge endpoint (bare form is a read), and
  action-aware deny remedies.
- Live validation during development: the INSTALLED plugin (3.69.2, pre-#107)
  false-positive-denied this session's own test and commit commands for
  containing gate phrases as data — the exact evasion-pressure failure mode
  this change eliminates.
- Reviews: code "With fixes" → fixes applied and empirically verified against
  the reviewer's own repro cases; governance APPROVE-WITH-NOTES.
