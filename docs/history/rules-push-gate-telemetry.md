# .claude/rules/push-gate-telemetry.md history

Narrative moved out of the path-scoped rule `.claude/rules/push-gate-telemetry.md` so
that the rule keeps only what a model must follow when it changes a push-gate shadow
corpus, its readers, or the diagnostic capture. The rule loads when the shadow libs and
adjudicators, `scripts/push-gate-capture.sh`, their tests, or the `implement-shadow-event`
and `review-verdict` OpenSpec changes are touched. Nothing loads this file; it exists so
the history is not lost. Each section reproduces the original unit **verbatim** (as of
commit `558c7b55`), names the test, if any, that now guards what was moved, and says
where its surviving instruction lives. Every section was moved in the commit
`docs: push-gate-telemetry rule keeps its instructions and moves test-guarded history to docs/history`
(the commit that created this file: `git log --diff-filter=A -- docs/history/rules-push-gate-telemetry.md`).

The fourth bullet, "REVIEW predicate 3, push-time stamps and `--evidence-miss`", was not
changed and has no section here.

## Preamble: "Path-scoped rule, split out of the repo-root `CLAUDE.md` ..."

Moved in: the commit named above. Guard: none. Its last sentence, "Every bullet is
verbatim", stopped being true when stage 1 of the prose cleanup and #379 edited the
bullets. Still in force: the preamble's first sentence, followed by a pointer to this
file.

Original text:

> Path-scoped rule, split out of the repo-root `CLAUDE.md` Gotchas section so it
> loads only when you touch the files it governs. Every bullet is verbatim.

## Bullet: "Push-gate **diagnostic capture** (`scripts/push-gate-capture.sh`, issue #127) ..."

Moved in: the commit named above. Moved, with the test that guards each:

- "The 26 deny records logged before the fix therefore carry **zero information** —
  pre-fix `allow` was produced for every replay that reached the decision point
  regardless of the real decision". Guard: `tests/test-push-gate-capture.sh` lines
  86-108 (a stub built from the guard's real deny-emitter line must classify `deny`;
  line 100 asserts the extraction found the emitter) and lines 130-142 (a live deny from
  the real guard replays as `deny`, "not a false drift signal"). The comment at lines
  86-93 records the field figure as 24/24; the rule's count was 26. The rule keeps "deny
  records logged before the fix carry zero information" and "NOT retro-classifiable"
  with its reason.
- "The stub-based tests passed throughout because they hand-wrote COMPACT JSON, i.e. they
  only ever proved the classifier agreed with the test's own idea of guard output." Same
  guard (lines 86-108, 130-142). Still in force as the reason clause after the rule's
  "Any test of an output classifier MUST derive its fixture from the real producer".

Other guards for what the rule still states: lines 19-52 (no raw command by default;
`command_sha`/`command_len`; full-command opt-in redacts), lines 63-67 (the log is
`0600`), lines 72-77 and 110-116 (sentinel-only replay is `allow`; an empty replay is
`incomplete`), lines 144-145 (one JSON object on stdout), lines 154-162 (the recursion
guard writes nothing and does not weaken the gate), lines 169-172 (not in
`_GATE_ENFORCE_LIBS`). Line 141 also covers "deny must be tested before the sentinel
branch", because the real guard's replay prints both. Not guarded by any test, so kept
in the rule: the never-`source`d rule and its reason, and the `${_rout//[[:space:]]/}`
prohibition and its timings.

Still in force: the bullet in the rule.

Original text:

> - Push-gate **diagnostic capture** (`scripts/push-gate-capture.sh`, issue #127) instruments `openspec-guard.sh` to catch the intermittent live-deny-while-replay-allows defect (`[[project_push_gate_unexplained_live_deny]]`, 2 hand-diagnosed occurrences; the instrument itself produced NO valid evidence until the classifier fix below, so do not re-inherit a "drift confirmed" reading from any pre-fix record). It runs ONLY from the guard's hardened EXIT trap as a **subprocess** — never `source`d on the decision path (a source-time Bash 3.2 error would trip the fail-open `trap 'exit 0' ERR` and skip enforcement; this was Codex P0). The trap does `trap - ERR; trap - EXIT; ( exec </dev/null >/dev/null 2>&1 … )` so it can never re-fire the ERR trap or leak a byte to stdout (the one-JSON-object contract). The guard's inline footprint is only a `_DECISION` var (default `allow`, set to `deny:<gate>` before each of the 7 deny `exit 0`) + the trap. Writes one compact JSONL record per push/merge to `~/.claude/.push-gate-invocation-log` (`0600` secured BEFORE first write, rotated to last 500). Raw command text is **NOT logged by default** (shell text can't be robustly de-secreted) — only `command_sha`+`command_len`+a coarse `command_label`; full best-effort-redacted text is opt-in via `PUSH_GATE_CAPTURE_FULL_CMD=1`. On a deny it runs a **true on-disk replay** (`PUSH_GATE_CAPTURE_DISABLE=1` recursion guard) and classifies it POSITIVELY as `ondisk_replay_decision` = `deny`/`allow`/`incomplete` — because the replayed guard is itself fail-open, it prints a `__PGC_EVALUATED__` sentinel (under `PUSH_GATE_CAPTURE_REPLAY=1`, never live) so an empty replay ≠ a genuine allow. `deny`+`allow` ⇒ live≠on-disk ⇒ **drift confirmed**; absence of any record for a live-denied push ⇒ the on-disk guard never ran ⇒ stale in-process/cached code (`guard_cksum`/`capture_error` disambiguate). Diagnostic-only → deliberately **EXCLUDED** from `_GATE_ENFORCE_LIBS`. **The replay classifier MUST match BOTH JSON forms:** the guard emits deny JSON via `jq -n`, which PRETTY-prints (`"permissionDecision": "deny"` — space after the colon, own line), while its advisory paths emit compact `printf` JSON. A compact-only needle silently classified **every** live deny as `allow` = "drift confirmed". The 26 deny records logged before the fix therefore carry **zero information** — pre-fix `allow` was produced for every replay that reached the decision point regardless of the real decision, and the records are NOT retro-classifiable (the JSONL deliberately omits `PGC_INPUT`, so no archived record can be replayed). The classifier matches both literal forms in one `case`; do NOT "simplify" it to `${_rout//[[:space:]]/}` — bash 3.2 bracket-class substitution is ~O(n^2.7) (110ms at 1KB, 24.5s at 8KB) and this runs synchronously in the guard's EXIT trap. Deny must be tested before the sentinel branch (the sentinel precedes every deny site, so a deny replay contains both). The stub-based tests passed throughout because they hand-wrote COMPACT JSON, i.e. they only ever proved the classifier agreed with the test's own idea of guard output. Any test of an output classifier MUST derive its fixture from the real producer (`tests/test-push-gate-capture.sh` greps the guard's actual emitter line) and assert the field end-to-end against the REAL guard, not only against stubs. Regression: `tests/test-push-gate-capture.sh`.

## Bullet: "The REVIEW shadow corpus was unreadable for a month and is NOT poolable (#239)."

Moved in: the commit named above. The bullet was rewritten around the decision that
closed its window. Every instruction, every pre-registration fact a future editor needs
(closed as a null result, flip not authorised, advisory by decision, constants not open,
the three things a successor must fix, both `predicate_version 2` grounds, the
pooled-episode test, `schema_version 2`) and every reader and test rule stays in the
rule, most of it in the original words. Moved:

- The accrual measurements: "measured 2026-09-23, 199 records / **99 episodes** / 5
  repos / **0 adjudications**, against a registered expectation of accruing *slower*
  than IMPLEMENT's 0.22 ep/day — observed **3.68 ep/day**, 17x the other way" and "The
  horizon clause (`computed ONCE at n=5, recorded in this file`) was never computed, and
  only the starvation backstop could ever have fired." Guard: none by a test; the
  decision record is `openspec/changes/review-verdict/design.md` lines 129-221 ("DECIDED
  2026-09-23" at line 131). The figures are reproducible by the instrument:
  `tests/test-review-shadow-adjudicate.sh` lines 661-674 (the excluded band is
  described as DESCRIPTIVE ONLY and its legacy episodes are grouped). The rule keeps 199
  records, 0 adjudications and "17x".
- The horizon reconstruction: "Reconstructing the horizon late does not settle it ...
  opposite outcomes, so "every reading is in the past" is true and conceals the only
  thing the clause protects." Guard: none by a test (design.md lines 177-191); moot
  since the window closed.
- The detail of the two senses of `n` ("the floor ("n=29 **at zero false blocks**") ...
  RECORDED ones (**99** on 2026-09-23)"), the pre-decision state of the backstop
  ("Before the decision below ... would have fired 2026-11-24"), "a draft of the
  amendment did exactly that and the sentence was retracted in review", "The amendment
  deliberately does NOT choose", "until the owner settled it, **no deadline was known to
  be live** ...", "The `n` ambiguity below is MOOT for this window and is retained as a
  defect for the NEXT registration to avoid", and the "Superseded standing conclusion,
  kept for the reasoning". Guard: none by a test (design.md lines 125-175); all moot
  since the window closed. The rule keeps a one-clause statement of the two senses
  inside "name `n` unambiguously", the instruction "Do not assert one while shipping the
  other", the reason "resolving a pre-registration's ambiguity after seeing the data is
  the discretion it exists to refuse", and "zero adjudications is not zero false blocks,
  it is no measurement".
- "(this repo's own drift canary fires on it)", "Corrected:", "(recorded late)", "and
  this is the evidence", and the long form of `schema_version 2` ("the guard passed
  `_proot` ... described a tree the decision was not about"). Guard:
  `tests/test-review-verdict.sh` lines 369-464 (8b: the shadow record names the SUBJECT
  branch, head AND repo, with a control) and lines 490-528 (8c: the version constants
  are exported and recorded). The rule keeps both version grounds and the
  subject-not-session statement.
- The first review round's narrative: "Review then found the instrument could certify
  the flip on bad evidence, three ways, all measured", the "29 adjudicated episodes in
  ONE repo plus a single UNLABELED episode ... band `DENY`" example and "the sibling
  `shadow-adjudicate.sh` already `continue`s past unlabeled/agent-claimed ... came out
  worse", "now resolved via", and the "(`FLOOR_EPISODES 29→1` + `FLOOR_REPOS 2→1` ⇒ 30/30
  PASS; `DENY_P 0.10→0.45` + `ADVISORY_P 0.20→0.99` ⇒ 30/30 PASS)" figures. Guards:
  `tests/test-review-shadow-adjudicate.sh` lines 417-462 (cell 12: the diversity branch
  is reached at n=29 and an unlabeled second-repo episode does not satisfy it, with a
  control), lines 464-526 (cell 13: two worktrees of one repository count once; a
  different repository counts twice; a path with a space counts once), lines 340-415
  (cell 11: five constants against `design.md`, `ALPHA` against a literal, and a floor
  of five matched constants).
- The second review round's narrative: "A SECOND review round then found five more, three
  of them wrong answers in the flip-clearing direction", the "`k=1 of n=2, NARROWED` to
  `k=0 of n=0, INSUFFICIENT`" example, "seconds after `--adjudicate` told the operator
  that row was excluded", "(latent, and the IMPLEMENT leg's rule 5 where dilution biased
  toward clearing)", the `_n_ok` mechanism of (d), and (e) "the floor message said `0
  episode(s) are recorded` three lines under `199 record(s)`". Guards: lines 567-612
  (cell 15: a truncated sidecar line does not discard later adjudications, with a
  control; corruption is announced; a record after a truncated corpus line is still
  addressable), lines 643-659 (cell 17: an agent `false_block` does not enter `k`),
  line 641 (a `would_block:false` record is not in the episode population), lines
  614-636 (cell 16: `--next` does not say "all labelled" with zero adjudications and
  says why nothing is offerable), lines 321-338 (cell 10: 40 unadjudicated episodes do
  not satisfy the floor), lines 661-674 (cell 18: the excluded band is described). The
  measured "prints `episodes 99 … span 26.88 day(s) … accrual 3.68 episodes/day`,
  matching what was published by hand" moved with it (cell 18 pins the description, not
  those figures).
- "PAIRED: a fourth, `an unreadable corpus reported as an empty one` ... is the same
  defect." Guard: lines 528-565 (cell 14: an unreadable corpus is reported as
  unreadable and never as a zero count, with a readable control) and lines 1044-1058
  (E10). The rule keeps the instruction and its mechanism.
- The third review round's narrative: "**A THIRD round then found the flagship cell
  CERTIFIED THE REGRESSION IT NAMES**, and this is the transferable one", "The rev-only
  cell had been added after `git -C <wt>` made the root redundant; the ROOT half was
  then left with nothing", "**Worse, the static companion behind it fell to a COMMENT**
  ... left the ENTIRE 74-cell file green, because `grep -A2 … | tr '\n' ' '` matched the
  name in the 3-line window", "**PAIRED: no cell connected the real producer to the
  real reader** ... renaming `would_block`→`wouldblock` or `ts`→`timestamp` ... (same
  symptom as the reader bug fixed the round before, different cause ...)", and "`_parsed`
  counted non-empty `.ts` so a valid `ts:""` record reported as an unparseable LINE".
  Guards: `tests/test-review-verdict.sh` line 437 (8b reads `.repo`) and lines 472-488
  (the call's second argument is literally `_SUBJ_ROOT` and its rev argument literally
  `_SUBJ_REV`, matched by position); `tests/test-review-shadow-adjudicate.sh` lines
  676-731 (cell 19: the real producer's record is grouped, offered by `--next`,
  addressable by `--adjudicate` and reaches the denominator), lines 733-761 (cell 20: a
  malformed-`ts` record is reported as excluded and not grouped, with a control), and
  lines 1031-1041 (E9b). The rule keeps each lesson as a test rule.
- "Two test cells here were vacuous and only mutation said so" was reworded as the
  heading of the rule's test rules. Guards: lines 77-119 (cell 2: the reader follows a
  MOVED producer constant, with the fixture asserted to have moved) and lines 196-225
  (cell 4: an empty-branch episode reaches the denominator).

Not guarded by any test, so kept in the rule: `LC_ALL=C sort` in the shared grouper
(no cell varies the collation), `shadow_band` erroring on ABSENT constants (cell 22,
lines 780-800, covers a degenerate `DENY_P=1`, not an absent one), the line-ordinal
caveat, the `| head -1` mutation note, and every pre-registration statement listed
above.

Still in force: the rewritten bullet in the rule. The fourth bullet's "the
pooled-episode test above" still resolves to it.

Original text:

> - **The REVIEW shadow corpus was unreadable for a month and is NOT poolable (#239).** `hooks/lib/review-shadow.sh` has appended a record per would-block since 2026-08-26, but **no reader existed** — `scripts/shadow-adjudicate.sh` is IMPLEMENT-only, and the sole consumer of `REVIEW_SHADOW_LOG` outside the writer was a test. So the pre-registration in `openspec/changes/review-verdict/design.md` reached its **n=29 floor on 2026-09-03 and nobody could see it**: measured 2026-09-23, 199 records / **99 episodes** / 5 repos / **0 adjudications**, against a registered expectation of accruing *slower* than IMPLEMENT's 0.22 ep/day — observed **3.68 ep/day**, 17x the other way. The horizon clause (`computed ONCE at n=5, recorded in this file`) was never computed, and only the starvation backstop could ever have fired. **A pre-registration with no instrument reaches its floor silently and stays advisory by inertia** — build the reader WITH the writer. Reconstructing the horizon late does not settle it: the two defensible readings of `observed_episodes_per_day_at_n5` give **2026-09-01 (n=21, below floor ⇒ the registered null result)** and **2026-09-10 (n=56, floor cleared)** — opposite outcomes, so "every reading is in the past" is true and conceals the only thing the clause protects. **The corpus is unpoolable for a reason predating all of this:** `78aa21e` (#219, 2026-09-01) moved THIS leg's own fire condition (`_diff_touches_material_source`, `review_verdict_covers_head`) onto the resolved subject, bumped `implement-shadow.sh`, and **left `review-shadow.sh` untouched** — so all 199 records say `predicate_version 1` while spanning two fire conditions, and a timestamp cannot recover which guard wrote one (sessions run cached plugin versions — this repo's own drift canary fires on it). Corrected: **`predicate_version 2` has TWO independent grounds** — `78aa21e`'s fire-condition change (recorded late), AND the recorder fix itself, because `repo`/`branch` ARE the episode key and `head_sha` is the adjudicator's anchor, so a session-derived branch can split one real episode into two (inflating n toward the floor) or send an adjudicator to the wrong branch's history. Recording only the first ground would invite re-pooling the old corpus later. **The stated rule "fire condition ⇒ predicate, describes ⇒ schema" HAS A GAP and this is the evidence:** the test is whether the change alters what a pooled EPISODE DENOMINATOR or a pooled true_catch/false_block LABEL means, not whether the leg fires differently — read it literally and you reach the wrong answer here in good faith.  `schema_version 2` is the recorder fix (the record now names the SUBJECT — the guard passed `_proot` while every predicate the leg fires on already took `_SUBJ_ROOT`/`_SUBJ_REV`, so `repo`/`branch`/`head_sha` — two thirds of the episode key plus the adjudication anchor — described a tree the decision was not about). **`n` IS USED IN TWO SENSES in that registration and they disagree about whether a deadline binds:** the floor ("n=29 **at zero false blocks**") needs ADJUDICATED episodes (**0** on 2026-09-23), while the backstop ("n<5 by 2026-11-24", sized against "0.22 **episodes/day**") and the horizon formula ("24 being the **episodes still needed**") are accrual arguments needing RECORDED ones (**99** on 2026-09-23). Before the decision below, under the recorded reading the backstop was dead; under the human-confirmed reading the reader actually ships, **the backstop was LIVE and would have fired 2026-11-24** as the registered permanent null result. Do not assert one while shipping the other — a draft of the amendment did exactly that and the sentence was retracted in review. The amendment deliberately does NOT choose (resolving a pre-registration's ambiguity after seeing the data is the discretion it exists to refuse); until the owner settled it, **no deadline was known to be live**, which reopened the "unbounded by construction" hole the backstop was written to close. **DECIDED 2026-09-23 — the window is CLOSED as a NULL RESULT** on the ground that it was never instrumented (owner ruling; the recommended route, rather than a choice between the `n` readings). The deny-flip is NOT authorised and the leg stays advisory **by decision, not default**; the backstop, the horizon and the 2026-10-27 override deadline are all SPENT with the window; the 199 records stay descriptive-only. The `n` ambiguity below is MOOT for this window and is retained as a defect for the NEXT registration to avoid. A successor window is deliberately NOT registered here — registering one is a separate act. **Three things a successor must fix:** name `n` unambiguously (one sense, no clause relying on the other); NAME THE ADJUDICATOR AND CADENCE (every safeguard here guarded accrual, and the corpus accrued 17x fast and stalled on human labelling nobody scheduled); and SHIP THE READER WITH THE WRITER. Superseded standing conclusion, kept for the reasoning: **the deny-flip criterion is NOT established and the leg stays advisory** — independent of the horizon, because the floor is *n=29 at zero false blocks* and **zero adjudications is not zero false blocks, it is no measurement**. The floor, bands, episode definition and `false_block` definition are NOT open. PAIRED: `scripts/review-shadow-adjudicate.sh` (diagnostic-only, excluded from `_GATE_ENFORCE_LIBS`) reports the excluded band **with its cause** — silently counting those records and silently dropping them are the same error facing opposite ways. `hooks/lib/shadow-corpus.sh` single-sources the band rule, the ISO→epoch prelude and episode grouping across BOTH legs; a new leg MUST use it rather than re-derive. **Two test cells here were vacuous and only mutation said so:** the version-derivation cell passed with the derivation deleted (the no-lib fallback literal equalled the producer constant — prove derivation by MOVING the producer, not reading it), and the empty-branch cell passed under the tab-IFS trap (the collapse shifts COLUMNS, so the row is still counted; what is lost is `_ids`, i.e. the episode silently leaves the DENOMINATOR while still being reported — assert it reaches the rate, never just that it was counted). A third mutation was a no-op that looked like a vacuous cell: `| head -1` on an awk that already prints one line. **Review then found the instrument could certify the flip on bad evidence, three ways, all measured:** (1) **diversity was counted over EVERY episode while the rate counted human-confirmed ones** — 29 adjudicated episodes in ONE repo plus a single UNLABELED episode in a second printed `floor met on n and diversity` with band `DENY`; the sibling `shadow-adjudicate.sh` already `continue`s past unlabeled/agent-claimed before accumulating the repo, so this was a re-derivation that came out worse. (2) **diversity was keyed on the WORKTREE path** (`--show-toplevel`), which is **15 distinct values for 5 repositories** on the live corpus, so ">=2 distinct repos" was satisfiable by two worktrees of ONE repo — now resolved via origin URL → `--git-common-dir` → path, the `branch_ledger_key` precedent. (3) **every pre-registered constant could be relaxed with a fully green suite** (`FLOOR_EPISODES 29→1` + `FLOOR_REPOS 2→1` ⇒ 30/30 PASS; `DENY_P 0.10→0.45` + `ADVISORY_P 0.20→0.99` ⇒ 30/30 PASS) because the band cell **set `ALPHA`/`DENY_P`/`ADVISORY_P` itself** — mutations picked from the test's own needles — and `FLOOR_REPOS` sat behind an `elif` no fixture ever reached. Constants are now cross-checked against `design.md` as a SECOND authority plus hardcoded literals as a third, with a **floor on the number of constants matched** so a reworded doc cannot make the greps silently match nothing. **A SECOND review round then found five more, three of them wrong answers in the flip-clearing direction:** (a) **three of four jq readers lacked the `-R fromjson?` guard the fourth justifies at length** — jq ABORTS on the first malformed line and returns what it parsed before, so one truncated SIDECAR line took the readout from `k=1 of n=2, NARROWED` to `k=0 of n=0, INSUFFICIENT` silently; the POSITION is the danger (a bad line at row 29 of 35 keeps rows 1-28, so a real `false_block` at row 34 vanishes while `n>=29` survives ⇒ **k falls and the band CLEARS**). (b) **an AGENT-claimed verdict entered the human-confirmed `k`** — worst-verdict-wins resolved over all rows while the episode reported `human` if ANY row was, seconds after `--adjudicate` told the operator that row was excluded. (c) `_episodes` did not filter `would_block == true` while `--next` did (latent, and the IMPLEMENT leg's rule 5 where dilution biased toward clearing). (d) `--next` printed `all N adjudicable record(s) are labelled` with **zero** adjudications, because `_n_ok` counted every record while the offer loop additionally required a well-formed `ts` and `would_block` — the "no records" vs "none countable" collapse **inside the message written to distinguish them**, and `ts:""` is producer-reachable (`date` failure). (e) the floor message said `0 episode(s) are recorded` three lines under `199 record(s)`. PAIRED: the excluded band is now DESCRIBED (episodes/span/accrual, labelled never-poolable) so the amendment's figures are reproducible BY THE INSTRUMENT — it prints `episodes 99 … span 26.88 day(s) … accrual 3.68 episodes/day`, matching what was published by hand; a legacy record has no `record_id`, so a line-ordinal stands in, which is safe ONLY because nothing is ever stored against it. Also `LC_ALL=C sort` in the shared grouper (a non-C collation can order two byte-different keys adjacently while awk compares `!=`, splitting an episode and INFLATING the denominator) and `shadow_band` now ERRORS on absent `ALPHA`/`DENY_P`/`ADVISORY_P` rather than defaulting — a band computed from probabilities nobody chose is worse than no band. PAIRED: a fourth, `an unreadable corpus reported as an empty one` (`-f` is not `-r`, and the count pipelines end in `tr` so the read error is discarded) — for an instrument whose whole purpose is stopping a live corpus from reading as empty, failing that on a different input is the same defect. **A THIRD round then found the flagship cell CERTIFIED THE REGRESSION IT NAMES**, and this is the transferable one: 8b's `shadow record names the SUBJECT branch+head` stayed **GREEN** with the guard reverted to `_proot` (the literal pre-fix state). Cause is the neighbour-mechanism trap, MIRRORED: the subject worktree and the session checkout **share refs and objects**, so `git -C <session root> rev-parse refs/heads/<subj>` returns the subject's sha — the REV alone supplies the right `branch`+`head_sha` whichever root is passed. The only field the ROOT determines is **`.repo`**, which the cell never read, and `.repo` is a third of the episode key. The rev-only cell had been added after `git -C <wt>` made the root redundant; the ROOT half was then left with nothing. **Worse, the static companion behind it fell to a COMMENT**: passing `_proot` and appending `# was _SUBJ_ROOT` left the ENTIRE 74-cell file green, because `grep -A2 … | tr '\n' ' '` matched the name in the 3-line window — match the ARGUMENT POSITION, never a substring of a neighbourhood. **PAIRED: no cell connected the real producer to the real reader** — every corpus was hand-built by a local `_rec()` that RETYPES the field names, so renaming `would_block`→`wouldblock` or `ts`→`timestamp` in the writer left BOTH files green while the real reader answered `all 1 adjudicable record(s) are labelled` for a never-adjudicated record (same symptom as the reader bug fixed the round before, different cause — the reader fix could not detect it). One round-trip cell calling `review_shadow_record` then `--next`/`--adjudicate`/`--status` closes the class. Also: a record that PARSES but has an unusable `ts` was dropped from the grouping silently (`2 parsed, 1 episode`, nothing said — `ts:""` is producer-reachable when `date` fails), and `_parsed` counted non-empty `.ts` so a valid `ts:""` record reported as an unparseable LINE. Regression: `tests/test-review-shadow-adjudicate.sh`, `tests/test-review-verdict.sh` (8b/8c).

## Bullet: "`scripts/shadow-adjudicate.sh` (Stage C2) labels IMPLEMENT shadow records ..."

Moved in: the commit named above. Moved, with the test that guards each:

- ", and the third was found only after the first two were fixed". Guard:
  `tests/test-shadow-adjudicate.sh` lines 122-129 (empty-branch and empty-token records
  still form episodes; `--next` keeps the transcript pointer and does not shift a
  column) and lines 490-493 (`--status` sees empty-branch episodes and COUNTS their
  adjudications).
- "Before that fix a human could adjudicate 29 empty-branch episodes and `--status`
  would still report `adjudicated 0`." Same guard (lines 490-493).
- "and the script had ZERO references to that field until 2026-08-27", "`_episodes()`
  pooled everything and `--next` queued attested non-blocks", and "Measured at the fix:
  17 records = **2 would-block + 15 attested**, so a reported backlog of "11
  unadjudicated episodes" was almost entirely the population that cannot produce the
  measurement (superseded; the honest figure is **2**)". Guard: lines 559-565 (`--next`
  does not offer an attested record and does offer a would-block one), lines 574-580
  (the two populations are reported separately and the rate denominator counts
  would-block episodes only), with the 17/2/15 fixture described at lines 537-543. The
  rule keeps "attested non-blocks cannot contain a false block by construction" and
  states the two consequences as instructions.

Other guards for what the rule still states: lines 33-38 (exact Clopper-Pearson bands;
8/23 is NARROWED), lines 59-89 (one retry burst is one episode; the window is anchored
at the first record; 1800 s inside, 1801 s outside), lines 184-213 (the shadow log is
untouched; `CLAUDECODE` and `CLAUDE_CODE_SESSION_ID` mark an agent), lines 234-239 (a
correction takes effect), lines 385-396 (a mixed episode resolves `false_block`;
agent-claimed episodes are excluded until a human re-confirms), line 472 (the floor binds
on rate-bearing episodes), lines 506-514 (not a gate-enforcement lib, not sourced by the
guard, no `permissionDecision`, never writes the shadow log), lines 591-604 (mixed
would-block/attested episodes count in either order; a missing `would_block` is reported
as excluded), line 676 (an attested episode does not satisfy the 2-repo floor). Not
guarded by any test, so kept in the rule: the removed tty check and its reason, the
inert `claude`-parent check and why ancestor-walking was reverted, the "never infer
membership from `impl_evidence_kind`" rule, and the no-version-bump reasoning.

Still in force: the bullet in the rule.

Original text:

> - `scripts/shadow-adjudicate.sh` (Stage C2) labels IMPLEMENT shadow records and reports the pre-registered rate. **Diagnostic-only** — never sourced by the guard, deliberately EXCLUDED from `_GATE_ENFORCE_LIBS`, emits no `permissionDecision`, writes no gate state (all pinned by `tests/test-shadow-adjudicate.sh`). Adjudications append to a SIDECAR (`~/.claude/.push-implement-adjudication.jsonl`, `IMPLEMENT_ADJUDICATION_LOG` overrides); the C1 shadow log is NEVER mutated. Four rules are easy to break: (1) the denominator is independent **episodes**, not records — `(repo, branch, session_token)` within 30 min **anchored at the episode's FIRST record**, not a rolling gap (a rolling gap chains a whole day into one episode); (2) bands are **exact Clopper–Pearson**, computed as a direct CDF comparison (`DENY ⟺ P(X≤k|n,0.10)<0.05`, `ADVISORY-ONLY ⟺ P(X≥k|n,0.20)≤0.05`) — Wilson is anti-conservative and calls 8/23 advisory where exact says narrowed, which is a pinned test; (3) agent-claimed adjudications are EXCLUDED from the rate until a human re-confirms, because this leg governs agent pushes and the subject has an incentive to self-grade; (4) claimant detection uses `CLAUDECODE` + `CLAUDE_CODE_SESSION_ID` (the repo's established marker) — a tty check was specified and REMOVED, because `[ ! -t 1 ]` fires on any redirect or pipe, and since human-claimed episodes are the only countable ones that silently makes the n=29 floor unreachable rather than costing a re-confirmation. The `claude`-parent check is INERT in this harness (Bash calls run under an intermediate shell, so `claude` is the grandparent); walking more ancestors was tried and REVERTED because inside a session every ancestry contains `claude`, making the human path untestable. Episode verdicts resolve **worst-verdict-wins** (any `false_block` wins) with the LATEST adjudication per record superseding earlier ones — folding over all rows made a correction a silent no-op. **THREE `IFS=$'\t' read` traps were removed, and the third was found only after the first two were fixed** — tab is IFS *whitespace*, so an empty field (e.g. the empty `branch` `implement-shadow.sh` writes when `rev-parse --abbrev-ref` fails) collapses and shifts every later column. In `_episodes` and `cmd_next` that dropped the record from the denominator / blanked the transcript pointer, fixed by splitting in `awk -F'\t'`. In `cmd_status` the loop must stay in the current shell (heredoc, so the counters survive), so it re-splits on **`\x1f`** via `tr '\t' '\037'` — `\x1f` is not IFS whitespace, so empty fields survive. Before that fix a human could adjudicate 29 empty-branch episodes and `--status` would still report `adjudicated 0`. PAIRED: never re-split tab-delimited data with bash `read`; use `awk -F'\t'`, or `tr` to `\x1f` when the loop body must mutate shell state. Floor binds on the rate's denominator, not the labelled count. **(5) The rate population is `would_block == true` ONLY, and the script had ZERO references to that field until 2026-08-27** — `_episodes()` pooled everything and `--next` queued attested non-blocks, which cannot contain a false block by construction. Measured at the fix: 17 records = **2 would-block + 15 attested**, so a reported backlog of "11 unadjudicated episodes" was almost entirely the population that cannot produce the measurement (superseded; the honest figure is **2**). Dilution here biases toward CLEARING the deny-flip — the unsafe direction. The filter is deliberately NOT inside `_episodes()` (shared; filtering there erases the attested population #169 exists to make visible), membership is read from the boolean and NEVER inferred from `impl_evidence_kind` (format-frozen, describes evidence not membership, and correlates only incidentally), and the **diversity floor moved too** — otherwise attestation episodes satisfy >=2 repos with zero false-block evidence spanning repos. Mixed episodes are classified by **ANY record would have blocked**, chosen because `_episodes()` anchors on the earliest record so an anchor-reading rule would classify by arrival order; both orders are pinned. A missing/non-boolean `would_block` is REPORTED as excluded, never coerced to false. No `predicate_version`/`schema_version` bump: this is a reader fix, the records and the firing predicate are unchanged. Regression: `tests/test-shadow-adjudicate.sh`.
