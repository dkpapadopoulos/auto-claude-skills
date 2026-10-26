# .claude/rules/test-suite.md history

Narrative moved out of the path-scoped rule `.claude/rules/test-suite.md` so that the
rule keeps only what a model must follow when it writes or changes tests. The rule loads
whenever `tests/**`, `.github/workflows/**`, `.verify.yml` or one of four skills is
touched, so in most coding sessions. Nothing loads this file; it exists so the history is
not lost. Each section reproduces the original unit **verbatim** (as of commit
`3cfe0c5f`), names the test, if any, that now guards the behaviour it described, and
says where its surviving instruction lives. Every section was moved in the commit
`docs: test-suite rule keeps its instructions and moves test-guarded history to docs/history`
(the commit that created this file: `git log --diff-filter=A -- docs/history/rules-test-suite.md`).
Review corrections to the notes (not to the quoted originals) followed in
`docs: test-suite rule claims only what is pinned; canary clause corrected`.

## Preamble: "Path-scoped rule, split out of the repo-root `CLAUDE.md` ..."

Moved in: the commit named above. Guard: none. Its last sentence, "Every bullet is
verbatim", stopped being true when stage 1 of the prose cleanup corrected false
statements in the bullets. Still in force: the preamble's first sentence, followed by a
pointer to this file.

Original text:

> Path-scoped rule, split out of the repo-root `CLAUDE.md` Gotchas section so it
> loads only when you touch the files it governs. Every bullet is verbatim.

## Bullet: "A capped `gh` query is byte-indistinguishable from a complete one (#209), and an undefined test function is silent."

Moved in: the commit named above. Guards:

- Truncation: `tests/test-improvement-miner.sh` lines 775-777 (at the cap the bundle
  exits non-zero and says "truncat"; run for the eval intake at 50 by line 788 and for
  the ledger at 200 by line 796), lines 779-781 (one below the cap is quiet; lines 792
  and 800), lines 818-826 (200 ledger issues stop the default cap, and
  `IMPROVEMENT_MINER_LEDGER_LIMIT=500` clears the stop), lines 827-830 (the error names
  that override). Not guarded by any test, so kept as instruction text in the rule: the
  guard counts only an array, and an absent limit returns instead of defaulting to `0`
  (the reasons are in comments at `skills/improvement-miner/scripts/mine-evidence.sh`
  lines 244-251).
- Wiring: `tests/test-suite-wiring.sh` lines 84-113 (red fixtures for
  defined-but-never-invoked, invoked-but-never-defined, both other definition forms, and
  an unreadable file, each asserting the named reason; a green small file passes),
  lines 122-139 (every `tests/test-*.sh` defining a `test_*()` function is swept, floor
  15), lines 167-193 (the mixed-shape file set is pinned by name), lines 198-240 (no
  file bumps `TESTS_PASSED`/`TESTS_FAILED` more often than `TESTS_RUN`, floor 5). The
  former live instance `test_no_stderr_without_explain` is invoked at
  `tests/test-routing.sh` line 3692. The zero-definitions floor
  (`tests/test-helpers.sh` lines 274-277) has no fixture of its own, so the general
  rule "a guard comparing two sets must check both differences and needs a floor"
  stays in the rule.

Still in force: two bullets in the rule, "A capped `gh` query ..." and "A test file's
bare call list ...". Dropped as history: the two limits' values, the no-live-instance
count (1 eval hit, 3 of 200 ledger runs), "123/123 green" from four undefined names, the
20-files count, the 496/500 counter story and the mutation-verification note.
Removed because false: "and trips the drift canary". The installed-plugin drift canary
(`hooks/session-start-hook.sh` lines 927-965) runs only when the session's cwd is the
plugin's own source repo, and its checksum manifest (line 957) does not include
`mine-evidence.sh`, so editing the cached script in a target repo can never trip it.
The same claim in the comment at `mine-evidence.sh` lines 292-300 was corrected in the
review-fix commit.

Original text:

> - **A capped `gh` query is byte-indistinguishable from a complete one (#209), and an undefined test function is silent.** `skills/improvement-miner/scripts/mine-evidence.sh` intakes two capped lists — eval reports at `--limit 50`, the run ledger at `--limit 200` — and neither noticed when the cap was REACHED, so the miner would quietly mine a partial corpus. The ledger is the severe one: it is the **kill-math source of truth**, so a silently dropped run moves the approved/presented counters that decide whether the skill decommissions itself. `assert_not_truncated <json> <limit> <what>` now fails loud on `length >= limit`, matching this script's existing posture that an incomplete bundle must never look like a complete one; the limits are VARIABLES so the check cannot drift from the query it guards, it counts only an ARRAY (`jq length` also counts object keys and string characters), and an absent limit returns rather than defaulting to `0` — which would have compared `0 >= 0` and bricked every run. **The ledger cap is a FORWARD-DATED HARD STOP**: the ledger grows one issue per run and is never pruned, so at run 200 both `bundle` and `dedup` would exit 5 permanently — and the obvious remedy ("raise the limit in mine-evidence.sh") is unapplicable in a target repo, where that file is the versioned plugin cache and editing it is undone by the next update and trips the drift canary. Hence `IMPROVEMENT_MINER_LEDGER_LIMIT`. Reaching the cap exactly counts as truncation because the two cases are indistinguishable from the client. **No live instance** — the eval query is SEARCH-scoped (`"Behavioral eval regression" in:title`, 1 hit today, which is why #94 surfaces at all despite 268 issues) and the ledger holds 3 of 200 — which is the reason it needed a test rather than a note to look again later. PAIRED, found while writing those cells and worth more than the fix: **a test file that ends in a BARE LIST OF FUNCTION CALLS is unchecked in BOTH directions, and each direction fails silently.** *Invoked but not defined*: bash prints `command not found`, the file keeps going, and `print_summary` still reports "All tests passed" with exit 0 — measured, four undefined names gave **123/123 green**. *Defined but not invoked*: the test simply never runs and nothing says so — **the live instance was `test_no_stderr_without_explain` (`tests/test-routing.sh`), defined and invoked nowhere, so it had never run; it is invoked now (#271).** The second direction is the one that quietly deletes coverage, and it is the one a one-directional guard misses. The run count is the only tell, and the size of the drop is test-specific (it equals that test's assertion count), so do not memorise a figure. `assert_test_functions_wired` (in `tests/test-helpers.sh`, so other files can adopt it) compares the DEFINED and INVOKED sets both ways **and carries a floor**: with no needles — an unresolvable path, a CRLF checkout, an indented call list — both sets are empty, every comparison trivially holds, and the guard would report a pass having checked nothing. **20 files had this shape when this was written and only one was guarded**; `tests/test-suite-wiring.sh` (#271) now sweeps EVERY `tests/test-*.sh` that defines a `test_*` function through `assert_test_functions_wired`, with a file-count floor (`tests/test-routing.sh` alone has over 200 bare calls). Adjacent, same theme: `test-routing.sh` used to report `Tests run: 496 / Tests passed: 500` — more passes than runs, because some arms bumped `TESTS_PASSED` without `TESTS_RUN`. That string is also what a previous session misread as a suite result, so it is worth knowing it was genuinely inconsistent rather than merely confusable; #271's second sweep now fails any test file whose direct `TESTS_PASSED`/`TESTS_FAILED` bumps outnumber its `TESTS_RUN` bumps. Regression: `tests/test-improvement-miner.sh` (both guards mutation-verified; removing either truncation call fails exactly its own two cells and not the other's).

## Bullet: "A review lead must isolate ONE fault before deciding a finding (#205)."

Moved in: the commit named above. Guard: `tests/test-review-adjudication.sh` lines
55-64 (four anchors hardcoded in the test must stay in the needle fixture), line 73 (the
needle count is pinned at 25), lines 76-85 (every needle in
`tests/fixtures/agent-team-review/adjudication/required-clauses.txt` appears in
`skills/agent-team-review/SKILL.md`; the needles cover the pair rule, the
masking-gate mechanism, both directions, `could-not-reproduce` keeping its severity,
the detached worktree, `git diff HEAD`, untracked files, the scope exception, the
oracle, the non-flip's three explanations, the comparable positive control, and a
`blocking` open finding constraining the verdict), lines 90-91 (step 4 of Lead
Synthesis routes to §4a), lines 100-105 (the seeded set keeps 3 REAL and 3 FALSE cells,
states its measured provenance, and names the REAL-1 clause in its bar). NOT pinned by
any needle or assertion, though written in SKILL.md: a `warning`-severity open finding
is `suggestions_only` at most (§5), and the reproduction worktree is reaped (§4a). The
default-config confounder, "sourced by the guard is not gates", and the memorisable-set
caveat are prose in `tests/fixtures/agent-team-review/adjudication/seeded-findings.md`,
not asserted. Not guarded by any test, so kept as instruction text in the rule: keep
assertion loops in the current shell (a redirect or a glob `for`, never a pipe); a
needle-fixture gate needs a second authority and a count floor; keep the §4a scope
exception; and the rule names the three unpinned sub-clauses above.

Still in force: the procedure itself in `skills/agent-team-review/SKILL.md` §4a and
§5, and the shortened "Review adjudication (#205)" bullet in the rule.

Original text:

> - **A review lead must isolate ONE fault before deciding a finding (#205).** `skills/agent-team-review/SKILL.md` §4a: reproduce with the claimed cause present and absent, everything else fixed, and require the two runs to **disagree**. Binds in BOTH directions — a finding "that failed to reproduce" is not refuted without the pair (say "failed to trigger", not "refuted"), and one accepted without a flipping pair is a guess with a file:line attached whose test asserts nothing. The mechanism: **an upstream fail-closed gate masks a downstream fall-open one**, so until every OTHER gate is independently satisfied the variable under test contributes nothing observable. Two confounder shapes are both live and only the first is obvious: a second injected fault, and **the DEFAULT CONFIG** — measured, `phase-evidence.sh` removed under `phase_enforcement.outbound: deny` flips deny→allow, while under the default `warn` both runs allow, so one reproduction on an untouched machine refutes a true finding. Unobtainable pair ⇒ `could-not-reproduce` + reason, severity PRESERVED, routed to the user as open (never a silent demotion). Reproduction runs in a **detached worktree** — adjudication injects faults on purpose, and doing that in the shared tree corrupts concurrent sessions and (per #219) measures a tree nobody is pushing. Pinned corpus: `tests/fixtures/agent-team-review/adjudication/seeded-findings.md`, 3 real-but-confounded + 3 false, **every cell measured against the real guard** (`git-command.sh` and `phase-evidence.sh` flip; `pr-diff.sh`, `implement-shadow.sh`, `push-gate-capture.sh` do not — "sourced by the guard" is not "gates"). **SCOPE, and getting it wrong repeals an existing rule:** §4a binds only on findings making an *experimentally decidable causal claim*, and explicitly NOT on `security`/`governance` findings blocking on the structural criterion the finding contract already allows — demanding a runnable pair for "this removes a safety constraint" would quietly delete that exception (caught in review). The oracle is whatever the finding predicts (a field, an exit code, an artifact), named BEFORE the run, not necessarily allow/deny. **A non-flipping pair is NOT proof of falsity** — three explanations (claim false / intervention incomplete / preconditions unmet) and the lead must name which; calling the last two "refuted" is the original mistake wearing a control. **PAIRED, and the first cut contradicted itself here:** a non-flip decides "false" ONLY once the other two are ruled out, and the way to rule them out is a **POSITIVE CONTROL** — a variable known to flip, run in the SAME harness. Without that, "it did not reproduce" and "it did not reproduce in a harness that provably reproduces something else" are indistinguishable, and only the second is evidence. That is precisely what makes the seeded set decidable: REAL-1 flips under the identical subject/control/preconditions the three FALSE cells use, so it IS their positive control. State it whenever you reject a finding. **An OPEN (`could-not-reproduce`) finding constrains the VERDICT, it is not neutral**: blocking-severity open ⇒ never `clean`/`suggestions_only` (route `blocking_issues`, name it, let the user decide explicitly); warning-severity open ⇒ `suggestions_only` at most. "We could not test it" is the most dangerous disposition because it reads as harmless. The finding contract gains an `Oracle:` line so the lead does not invent the oracle after seeing the result. **The reproduction worktree's uncommitted delta is `git diff HEAD`, NOT `git diff <base_sha>`** — base..head is already IN the checked-out sha, so the latter re-applies committed changes on top of themselves; untracked files are in neither and must be copied explicitly. The reproduction worktree must carry the REVIEWED change: `git worktree add --detach <wt> <head_sha>` adjudicates the PARENT state for uncommitted work, so apply the diff explicitly, and reap the worktree. Bar is >=5/6 AND REAL-1 classified REAL: that clause is not redundant, REAL-1 is the one whose naive reproduction argues for the wrong answer — but **the bar is prose that nothing enforces, and the set is memorisable** (every REAL cell is a `_GATE_ENFORCE_LIBS` member, every FALSE cell advisory/diagnostic, so a keyword rule scores 6/6 constructing no control), so it is a set of worked examples, never a certification. Gate: `tests/test-review-adjudication.sh` — two authorities (fixture needles + anchors hardcoded in the test) plus a count floor, mutation-verified 3/3. PAIRED: its loops are **heredoc-fed, never piped** — the first cut piped them, so `_record_pass`/`_record_fail` ran in a subshell, and mutating a clause out of SKILL.md printed one FAIL while the summary still read 9/9 and exited 0. Any assertion loop in a test file must run in the current shell.

## Bullet: "The 150,000-char instruction-file limit is a TOTAL across files ..."

Moved in: the commit named above. Guard: `tests/test-claude-md-rule-split.sh` LEG 7,
lines 421-422 (every instruction file within 200 lines and 4 MiB), lines 438-444 (the
session-start total is asserted against 150,000), lines 448-459 (the all-files total is
an equality ratchet: growth and an unbanked shrink both fail), lines 463-466 (the true
percentage is printed every run), lines 597-603 (a scoped rule is outside the
session-start total, an unscoped or unreadable one is inside). The leg's header, lines
228-322, carries the #96506 product string, the docs quotes and the measured history
(`63564586` 154,492 chars, `089701b8` 23,083, the `InstructionsLoaded` probe).

Still in force: the shortened bullet in the rule, which keeps the total-not-per-file
fact, scoped versus unscoped loading, the instruction not to replace the ratchet with
the real limit and why, the same-commit baseline convention, and the transferable
lesson about a per-file budget against a combined limit.

Original text:

> - **The 150,000-char instruction-file limit is a TOTAL across files, not a per-file cap, and it warns about CONTEXT COST — nothing is ever truncated.** Product string, anthropics/claude-code#96506: `N instruction files add up to 192.2k chars, over the 150.0k-char total limit ... /memory to free up context`. A rule file WITH `paths:` frontmatter loads on demand, not at launch, so it is NOT in the session-start total (measured via an `InstructionsLoaded` hook: `load_reason=path_glob_match` for rules vs `session_start` for CLAUDE.md) — which is why the split WORKED: `63564586` was 154,492 chars at session start (102%, genuinely over), `089701b8` 23,083 (15%), 25,140 (17%) on 2026-10-01. What grows instead is the WORST CASE, every rule loaded in one session, now over 100% (LEG 7 prints the current percentage every run) — real, but a cost paid on demand. An UNSCOPED rule file does load at launch and does count. The docs quantify only "target under 200 lines per CLAUDE.md file" and a 4 MiB hard SKIP (a larger file does not load at all); the combined limit's existence is documented, its value is not. LEG 7 of `tests/test-claude-md-rule-split.sh` asserts those two per-file rules and RATCHETS the combined byte total, failing on growth and on an unbanked shrink, printing the true percentage every run. A ratchet rather than the real limit because asserting 150,000 goes red today and `.verify.yml` makes the whole suite the push gate — one red cell denies every routing push repo-wide. Raising the baseline is allowed but never silent: same convention as `INCIDENT_SKILL_WORD_BASELINE`, raise it in the same commit and say why. **The transferable lesson:** a per-file budget against a combined limit is the wrong SHAPE, not the wrong number — 130k across 8 files permits 6.9x the limit, green throughout.
