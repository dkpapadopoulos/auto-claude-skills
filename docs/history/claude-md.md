# CLAUDE.md history

Narrative moved out of the repo-root `CLAUDE.md` so that the always-loaded file keeps
only what a model must follow at write time. Nothing loads this file; it exists so the
history is not lost. Each section reproduces the original unit **verbatim** (as of
commit `a9e8f753`), names the test, if any, that now guards the behaviour it described, and
says where its surviving instruction lives. Every section was moved in the commit
`docs: CLAUDE.md keeps its instructions and moves test-guarded history to docs/history`
(the commit that created this file: `git log --diff-filter=A -- docs/history/claude-md.md`).

## Skill-creation flow: "The enforceable done-gate ..." paragraph

Moved in: the commit named above. Guard: `tests/test-done-gate-ci.sh` (lines 38-45 assert the workflow RUNS each gate; line 60 asserts every invocation closes stdin). Still in force: the shortened paragraph in CLAUDE.md.

Original text:

> The **enforceable done-gate** is owned and deterministic, and now covers **two** artifacts per owned, trigger-routed skill: (1) a routing fixture `tests/fixtures/routing/<name>.txt` with >=1 `MATCH` line and >=1 verbatim-borrowed `NO_MATCH` decoy (`tests/test-fixture-coverage.sh`); and (2) a content-assertion test — some `tests/*.sh` must reference `skills/<name>/` (`tests/test-skill-content-coverage.sh`, content-based/naming-agnostic). Both run in CI on every PR via `.github/workflows/done-gates.yml` (hard-blocking only once marked Required in branch protection — see `docs/CI.md`); regression `tests/test-done-gate-ci.sh` pins that workflow so the claim cannot rot. **`.verify.yml` is the LOCAL gate** (`substrate: local`) — read by the push gate and `project-verification`, by no workflow — so the full `tests/run-tests.sh` suite is NOT a CI check. The external skills (`writing-skills`, `skill-creator`) are recommended quality layers — they are not merge preconditions.

## Style: "Session-start hook budget is stated as 200ms ..." (hook latency)

Moved in: the commit named above. Guard: none; the full measurements are kept here. Still in force: the shortened "Hook latency targets" bullet in CLAUDE.md.

Original text:

> - Session-start hook budget is stated as 200ms; measured 2026-10-12 it takes ~1.6 s with twelve plugins (2,531 to 1,624 ms across PR #348). The activation hook runs on every prompt: measured 2026-10-12 at a 172 ms median on one prompt (20 runs) and 178 ms on a chained render (a separate 15-run measurement), against a stated target of ~50 ms. Treat both stated numbers as targets, not facts. Minimize jq forks — batch into single calls.

## Gotchas: "The model's Bash tool is NOT bash ..." (zsh)

Moved in: the commit named above. Guard: `tests/test-phase-attest-shell-portability.sh` (lines 93/97 self-location and own-session token, 103/106 dash degradation, 112 unmatched glob, 116/124 gating-milestone membership, 142 bare-name `$0`; each per shell). Still in force: the shortened bullet in CLAUDE.md (the model shell, scalar splitting) and the sourced-lib bullet in `.claude/rules/shell-portability.md` (the three lib traps).

Original text:

> - **The model's Bash tool is NOT bash — it is the user's shell (zsh 5.9 on macOS), and the whole test suite runs under bash.** Any `hooks/lib/*.sh` a SKILL.md or hint tells the model to `source` therefore executes under zsh in production and under bash in CI, so zsh incompatibilities pass every gate and fail silently for real users. **This is not only a *lib* concern — every ad-hoc command the model writes runs under zsh too** (measured 2026-07-28: `$0=/bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset), so bash-shaped throwaway shell fails the same way with no error. Scope is narrower than it looks: zsh DOES split unquoted **command substitution**, so `for f in $(git ...)` is safe; only unquoted **scalar** expansion breaks — `V="a b c"; for x in $V` runs ONCE and `set -- $V` leaves `$#=1`. Both exit 0, so the only tell is an impossibly clean result (zero files copied; four "different" measurement runs that are byte-identical — both observed in one session, 2026-07-28). Write the list literally, feed it through `printf '%s\n' … | while IFS= read -r`, or use an array. Three distinct lib-side instances shipped undetected and were fixed together in PR #165: (1) **`${BASH_SOURCE[0]}` is EMPTY in zsh** — `$(dirname "${BASH_SOURCE[0]}")` collapses to `dirname ""` = `.` = the **CWD**, so `phase-attest.sh` never found its sibling `session-token.sh`, `resolve_own_session_token` stayed undefined, and the token fell back to the singleton, making the #151/#156 own-session-first fixes **inert on the model-turn path they were written for**. Use `${BASH_SOURCE:-}` (bare = element 0 in bash, a valid empty scalar elsewhere); **`${BASH_SOURCE[0]:-}` is a fatal `Bad substitution` in dash** (Linux `/bin/sh`; macOS `/bin/sh` is bash 3.2 and will NOT reproduce it, so test with `dash` explicitly) because the subscript is in the *name*, killing the whole lib instead of degrading. zsh sets `$0` to the sourced file, so it is a usable fallback — but accept it ONLY when it carries a directory *and* names this file (`*/name.sh`): a bare basename yields `.` = CWD and provably sources an attacker-planted `./session-token.sh`. (2) **An unmatched glob is FATAL in zsh** and unwinds the enclosing function, so any fallback *after* a `for f in <glob>` loop never runs (`resolve_own_session_token` returned an EMPTY token instead of the singleton — worse than a scatter, per the #157 analysis). Guard **inside a function** with `if [ -n "${ZSH_VERSION:-}" ]; then setopt local_options no_nomatch 2>/dev/null; fi` — zero forks, and bash never executes it. Use the `if` block, NOT `[ … ] && setopt …`: the `&&` form returns **exit 1** in bash/dash (measured) and flips the return code of any function it ends — the same silent-failure class this bullet exists to prevent. `local_options` restores on **function return only**; at file top level it leaks `no_nomatch` into the model's shell for the rest of that Bash call. Prefer it over `find` on hook hot paths. (3) **zsh does not word-split unquoted scalars**, so `for x in $LIST` iterates ONCE over the whole string — this silently defeated BOTH gating-milestone locks in `phase-attest.sh` (a `requesting-code-review` attestation actually recorded). Use `case " $LIST " in *" $item "*)`. All three fail **open and silent**. PAIRED: when touching a model-sourced lib, assert its contracts in every shell (bash/zsh/sh/dash) with the bash leg kept as an explicit control, and derive per-shell expectations from a separate capability probe rather than hardcoded shell names (dash has no self-location, so its correct behavior is *degradation*, not success). Regression: `tests/test-phase-attest-shell-portability.sh`. `phase-evidence.sh` shares the `BASH_SOURCE` pattern but is hook-only (`#!/bin/bash`), so it is unaffected — re-check that if it ever becomes model-sourced.

## Gotchas: "Grepping runtime text output ..." (grep -F)

Moved in: the commit named above. Guard: none needed (write-time guidance). Still in force: the shortened bullet in CLAUDE.md.

Original text:

> - Grepping runtime text output (CLI/log streams, not source — Serena/LSP don't apply): use `grep -F` (or `\[ERROR\]`) when matching literals containing regex metacharacters. `grep "[ERROR]"` is a character class matching any of `E,R,O` and silently returns wrong lines; `grep "v1.9.0"` matches `v1X9Y0` because `.` is a wildcard. Bites `incident-analysis` (log-level greps), `behavioral-evaluation` (version-string assertions), and any future runtime-output parser.

## Gotchas: "skills/incident-analysis/SKILL.md has a word-count ratchet ..."

Moved in: the commit named above. Guard: `tests/test-incident-analysis-content.sh` (line 820: CLAUDE.md must say `ratchet`; 835: growth fails; 845: a cut of 250+ words fails). Still in force: the shortened bullet in CLAUDE.md.

Original text:

> - `skills/incident-analysis/SKILL.md` has a word-count **ratchet**, not a fixed ceiling — `INCIDENT_SKILL_WORD_BASELINE` in `tests/test-incident-analysis-content.sh` is pinned to the file's exact current size, so headroom is deliberately ZERO: any growth fails, and so does a shrink of 250 or more words, until the constant is edited. That visibility is the control; the number is not sacred. Growing it: extract tables, YAML schemas (>15 lines), URL templates and rationale to `references/` FIRST, then raise the constant in the same commit and say why in the message. Shrinking it: lower the constant in the same commit — a shrink of 250 or more words fails a staleness leg, and a smaller one passes and is banked as new slack. This replaced a fixed 11,500 ceiling that had drifted to 66 words of headroom while never once forcing a reduction — do not restate that number as the limit, because it permitted regrowth up to the cap, which is a ratchet in the wrong direction.

## Gotchas: "tests/run-tests.sh self-guards stdin ..." (#142)

Moved in: the commit named above. Guard: `tests/test-suite-stdin-guard.sh` (line 161: the runner terminates on a never-EOF FIFO; 189-195: the red control must change the runner, `cmp -s`; 199: without the guard it hangs) and `tests/test-done-gate-ci.sh` line 60 (CI steps redirect stdin). Still in force: the shortened bullet in CLAUDE.md.

Original text:

> - **`tests/run-tests.sh` self-guards stdin (`exec < /dev/null`, #142) — every OTHER invocation still must not (`< /dev/null` stays mandatory).** Hooks read their payload from stdin, and `session-start-hook.sh` does it behind `[ ! -t 0 ]` — **a TTY check is not an "input available" check**: a socket or FIFO is not a TTY, so `$(cat)` runs and blocks forever waiting for an EOF that never arrives. ~15 test call sites invoke that hook with no redirect and inherit fd 0, so before the runner guard a suite launched with socket stdin (routine in an agent session) parked mid-run at near-zero CPU with **no error** — one run idled ~2h, and it reads as "slow suite", not as a bug; the tell is `lsof -p <pid> -d 0` showing fd 0 on a socket. The runner guard is inherited by every discovered file at once (114 when it landed, 202 on 2026-10-25), but covers ONLY `run-tests.sh`: `bash tests/test-context.sh`, `bash hooks/session-start-hook.sh`, and any CI step invoked directly still hang without their own `< /dev/null` — which is why `.github/workflows/done-gates.yml` carries the redirect on every step with a comment calling it "REQUIRED, not decorative". The deeper `[ ! -t 0 ]` fix is deliberately NOT done (hardening a fail-open, gate-adjacent hook is a different risk class). Regression: `tests/test-suite-stdin-guard.sh`, which drives a copy of the real runner over a FIFO under an inline watchdog (macOS has no `timeout(1)`) and carries a red control so it cannot go vacuous. PAIRED: that control must assert the strip **changed** something (`cmp -s`) — asserting only "the guard pattern is absent from the stripped copy" is equally true when the strip worked and when the pattern never matched, so it passed with the guard deleted from main until review mutation-tested it.

## Gotchas: "A suite log is COMPLETE only if it says so ..." (#263)

Moved in: the commit named above. Guard: `tests/test-suite-completion.sh` (186-225: every exit code, a vacuous run, two sentinels, sentinel not last; 248-257: INT64, octal, contradicted and unrecognised status; 266-270: `--min-files`; 298/300: zero `FAIL:` lines yet incomplete; 319-324: mutation; 336-342: only the runner emits it; 360/369: the known limit). Still in force: the shortened bullet in CLAUDE.md.

Original text:

> - **A suite log is COMPLETE only if it says so — `tests/run-tests.sh` now emits a sentinel, and nothing else may stand in for it (#263).** The runner's terminal block (`Files run:` / `Files passed:` / `Files failed:` inside a `====` frame) is **shape-identical** to the block `tests/test-helpers.sh::print_summary` emits at the end of EVERY individual test file (`Tests run:` …, same four-space padding, same frame) — one word apart. So a reader that lands on a per-file block, tailing a running log or reading one reaped partway, cannot tell it from the runner's own end. Completion was therefore assertable only by ABSENCE, and **nothing in the repo asserted it** (measured: zero consumers of `Files run:` outside the runner). Measured 2026-08-27 on a real reaped run: **91 of 122 files executed, thousands of PASS assertions, zero `FAIL:` lines** — every signal a normal check inspects said green, and the failure direction is CLEAN, which CI goes green on. Two shapes produce it: `nohup … &` inside a backgrounded Bash call (reaped with its parent's process group) and the harness auto-backgrounding any call over ~120s (this suite is ~13 min), after which the result is never handed back. **The rule: gate a pass claim on the sentinel's PRESENCE, never on the absence of `FAIL:` lines** — the latter is equally true of a suite that never started. `scripts/assert-suite-complete.sh <log>` is the supported reader and has **four** outcomes, never two: `0` complete+pass (the only state licensing the claim), `1` complete-but-not-a-pass (truncated, **vacuous — a run over 0 files is not green**, or malformed), `2` complete+FAILED, `3` **cannot check** (no argument, missing, unreadable, whitespace-only). `3` is separate from `1` deliberately: a checker that reports clean when it could not parse its input is worse than no checker. PAIRED: `verify-and-record.sh` is UNAFFECTED — it waits on the command and keys PASS to exit 0, which is correct; the defect only ever hit readers of a log. The portable half of the rule (never key a pass claim on absent failure markers; if the runner has no completion marker, re-run it synchronously) is in `skills/project-verification/SKILL.md`, because the sentinel itself is this repo's runner and cannot be assumed in an installer's repo. **KNOWN LIMIT, do not overstate it:** the sentinel is a CONVENTION enforced by a source grep, not a property. A test file printing the literal string as its own last line, in a run reaped at exactly that instant, reads as complete — pinned as an explicit `KNOWN LIMIT` cell rather than papered over. What IS a property: a suite that runs to its end then carries TWO sentinels, and two are rejected. `--min-files N` covers the other way a suite fails to run in full — the sentinel proves the runner reached its END, not that its glob DISCOVERED everything, so a partial checkout yields a smaller, well-formed, entirely green run. **Nothing invokes the checker automatically**, and that is inherent: the synchronous path is already correct via the exit code, and the defect only reaches a human or agent *reading a log*, whom no gate can compel. It is in the Commands table so it is findable. Regression: `tests/test-suite-completion.sh` — fixture logs are produced by the REAL runner copied verbatim and then cut, never hand-written (a hand-written fixture only proves the checker agrees with the test's own idea of the format; the two negative fixtures, an empty and an unstructured log, are necessarily synthetic). It carries a mutation cell that removes the feature (function AND call sites, not just the printf — stripping the printf alone leaves a broken runner, which is a different counterfactual) and a paired end-to-end cell asserting the truncated log has **zero** `FAIL:` lines **and** is still reported incomplete — asserting only the second half would pass even if the naive check already caught it. Review added six cells for branches no cell reached: mutating the unrecognised-status arm to exit 0 left the file 25/25 green. **The Critical it missed is the transferable one:** `case ''|*[!0-9]*` admitted counts that `[ -ne ]` and `$(( ))` then FAILED to evaluate — past `INT64_MAX`, or a leading-zero octal trap like `08` — and with no `set -e` the failing comparison printed to stderr and execution fell THROUGH to the `status=pass` branch and `exit 0`. A validator that accepts what the later arithmetic cannot evaluate turns a parse failure into a clean pass, which is exactly the thing the script exists to forbid; `_is_count` now bounds the length and rejects leading zeros so the arithmetic is total. And `sentinel-not-last` was satisfied by the FALLBACK path — the appended junk line tripped the malformed-fields branch instead, so the cell passed with the whole last-line check deleted; its trailing line must itself PARSE.

## Path-scoped rule files: section preamble and filing criterion

Moved in: the commit named above. Guard: `tests/test-claude-md-rule-split.sh` LEG 5 (lines 209-215 pin the four misfiled bullets to CLAUDE.md); the LEG 4 comment (lines 143-148) repeats the `config/*.json` argument. Still in force: the shortened preamble and filing paragraph in CLAUDE.md.

Original text:

> The rest of this section lives in `.claude/rules/*.md`, each scoped with `paths:`
> frontmatter so it loads when you touch the files it governs rather than every
> session. The prose is verbatim — nothing was summarised in the move.
>
> **The filing criterion is whether the guidance needs a file open, NOT its subject
> matter.** A bullet governing your own shell, your own tool calls, or how you read
> command output has no triggering file and therefore stays HERE — that is why the
> zsh, `grep -F`, stdin-guard and suite-sentinel bullets above are in this file even
> though they are "about" tests and shell. Filing those four by topic was the first
> mistake this split made; four of thirty were misfiled that way. When adding a
> bullet, ask what would have to be open for it to load, and if the answer is
> "nothing in particular", it belongs above.
>
> A bullet that merely *mentions* a file in passing is deliberately NOT globbed onto
> it — only the surfaces a bullet governs. In particular `push-gate-enforcement.md`
> does not glob `config/*.json`: those preconditions are `remedy-reachability.md`'s
> subject, and re-adding them here would pull 62k into the ~85% of commits that touch
> config, which is the cost this split exists to avoid.
>
> **If you are reasoning about one of these surfaces without opening a file that
> triggers the rule, read the file directly**; a path-scoped rule does not load on
> reasoning alone, and does not come back after `/compact` until a matching file is
> read.

