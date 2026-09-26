# auto-claude-skills

Claude Code plugin for automatic skill routing based on prompt intent and SDLC phase.

## Commands

| Command | Description |
|---------|-------------|
| `bash tests/run-tests.sh` | Run all test suites |
| `bash scripts/assert-suite-complete.sh [--min-files N] <log>` | Decide whether a suite LOG represents a run that finished (0 complete+pass, 1 not-a-pass, 2 complete+failed, 3 cannot-check) |
| `bash tests/test-routing.sh < /dev/null` | Test skill routing engine |
| `bash tests/test-registry.sh < /dev/null` | Test registry building and merging |
| `bash tests/test-context.sh < /dev/null` | Test context formatting and phase composition |
| `bash -n hooks/<name>.sh` | Syntax-check a hook (no execution) |
| `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh < /dev/null` | Debug routing with explanation output |

## Architecture

- **Two main hooks**: `session-start-hook.sh` builds the skill registry at session start; `skill-activation-hook.sh` scores and routes on every prompt.
- **Registry**: Cached at `~/.claude/.skill-registry-cache.json`. Merged from `config/default-triggers.json` + plugin discoveries + `~/.claude/skill-config.json` overrides.
- **Scoring**: Regex trigger match → base score + priority + name bonus + composition bonus → role-cap selection (max 1 process, 2 domain, 1 workflow).
- **Output**: JSON via `hookSpecificOutput` on stdout. Hooks fail-open (exit 0 on error).

## Skill-creation flow

Three-stage division of labor for building new skills:

1. **`writing-skills`** (DESIGN phase, `role=required`, always fires) — enforces discipline, anatomy completeness, and a failing pressure-test before a line of implementation is written.
2. **`skill-scaffold`** — emits seed files including the routing fixture stub (`tests/fixtures/routing/<name>.txt`) and an evals stub; provides the mechanical skeleton for the next two stages.
3. **`skill-creator`** (REVIEW phase, advisory) — validates triggering on a held-out prompt set before merge; catches over/under-matching that unit tests miss.

The **enforceable done-gate** is owned and deterministic, and now covers **two** artifacts per owned, trigger-routed skill: (1) a routing fixture `tests/fixtures/routing/<name>.txt` with >=1 `MATCH` line and >=1 verbatim-borrowed `NO_MATCH` decoy (`tests/test-fixture-coverage.sh`); and (2) a content-assertion test — some `tests/*.sh` must reference `skills/<name>/` (`tests/test-skill-content-coverage.sh`, content-based/naming-agnostic). Both run in CI on every PR via `.github/workflows/done-gates.yml` (hard-blocking only once marked Required in branch protection — see `docs/CI.md`); regression `tests/test-done-gate-ci.sh` pins that workflow so the claim cannot rot. **`.verify.yml` is the LOCAL gate** (`substrate: local`) — read by the push gate and `project-verification`, by no workflow — so the full `tests/run-tests.sh` suite is NOT a CI check. The external skills (`writing-skills`, `skill-creator`) are recommended quality layers — they are not merge preconditions.

## Doc locations

Six canonical homes for project context. Read this before guessing where docs live.

- `CLAUDE.md` (repo root) — project instructions, always auto-loaded into every session.
- `docs/plans/` — design docs (`*-design.md`) and task plans (`*-plan.md`). Gitignored; per-session scratch. Default mode persists design intent here.
- `openspec/changes/` — committed proposals/specs visible to teammates. Only used in `spec-driven` preset (see Spec Persistence Modes).
- `~/.claude/projects/<project>/memory/MEMORY.md` + sibling memory files — auto-memory across sessions (typed frontmatter, slug-indexed). Project-local conversation memory.
- `.claude/knowledge/` — committed, human-gated team facts (OKF/auto-memory shaped; one markdown file per fact with YAML frontmatter). Read at session-start as the base tier (index.md injected, capped at 8192 bytes, fail-open). Optionally mirrored to each user's local Forgetful for semantic retrieval via `scripts/knowledge-forgetful-map.sh`. Validated by `scripts/knowledge-validate.sh`. Note: repos that gitignore `.claude/` wholesale must un-ignore this dir with `!.claude/knowledge/` or committed facts will not travel with the repo.
- `.claude/` — plugin runtime state, hooks, settings, and worktrees.

## Style

- Bash 3.2 compatible (macOS `/bin/bash`). No associative arrays.
- 200ms session-start hook budget. Activation hook is faster (~50ms). Minimize jq forks — batch into single calls.
- Field separator: `\x1f` (US). Intra-field delimiter: `\x01` (SOH). Never `\n` inside fields.
- Commit messages: `<type>: <description>` (fix, feat, docs, test, refactor).
- When editing files, never replace full content if only a section needs changing. Preserve existing data in YAML/JSON files. Use targeted edits, not full-file rewrites.

## Gotchas

- **The model's Bash tool is NOT bash — it is the user's shell (zsh 5.9 on macOS), and the whole test suite runs under bash.** Any `hooks/lib/*.sh` a SKILL.md or hint tells the model to `source` therefore executes under zsh in production and under bash in CI, so zsh incompatibilities pass every gate and fail silently for real users. **This is not only a *lib* concern — every ad-hoc command the model writes runs under zsh too** (measured 2026-07-28: `$0=/bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` unset), so bash-shaped throwaway shell fails the same way with no error. Scope is narrower than it looks: zsh DOES split unquoted **command substitution**, so `for f in $(git ...)` is safe; only unquoted **scalar** expansion breaks — `V="a b c"; for x in $V` runs ONCE and `set -- $V` leaves `$#=1`. Both exit 0, so the only tell is an impossibly clean result (zero files copied; four "different" measurement runs that are byte-identical — both observed in one session, 2026-07-28). Write the list literally, feed it through `printf '%s\n' … | while IFS= read -r`, or use an array. Three distinct lib-side instances shipped undetected and were fixed together in PR #165: (1) **`${BASH_SOURCE[0]}` is EMPTY in zsh** — `$(dirname "${BASH_SOURCE[0]}")` collapses to `dirname ""` = `.` = the **CWD**, so `phase-attest.sh` never found its sibling `session-token.sh`, `resolve_own_session_token` stayed undefined, and the token fell back to the singleton, making the #151/#156 own-session-first fixes **inert on the model-turn path they were written for**. Use `${BASH_SOURCE:-}` (bare = element 0 in bash, a valid empty scalar elsewhere); **`${BASH_SOURCE[0]:-}` is a fatal `Bad substitution` in dash** (Linux `/bin/sh`; macOS `/bin/sh` is bash 3.2 and will NOT reproduce it, so test with `dash` explicitly) because the subscript is in the *name*, killing the whole lib instead of degrading. zsh sets `$0` to the sourced file, so it is a usable fallback — but accept it ONLY when it carries a directory *and* names this file (`*/name.sh`): a bare basename yields `.` = CWD and provably sources an attacker-planted `./session-token.sh`. (2) **An unmatched glob is FATAL in zsh** and unwinds the enclosing function, so any fallback *after* a `for f in <glob>` loop never runs (`resolve_own_session_token` returned an EMPTY token instead of the singleton — worse than a scatter, per the #157 analysis). Guard **inside a function** with `if [ -n "${ZSH_VERSION:-}" ]; then setopt local_options no_nomatch 2>/dev/null; fi` — zero forks, and bash never executes it. Use the `if` block, NOT `[ … ] && setopt …`: the `&&` form returns **exit 1** in bash/dash (measured) and flips the return code of any function it ends — the same silent-failure class this bullet exists to prevent. `local_options` restores on **function return only**; at file top level it leaks `no_nomatch` into the model's shell for the rest of that Bash call. Prefer it over `find` on hook hot paths. (3) **zsh does not word-split unquoted scalars**, so `for x in $LIST` iterates ONCE over the whole string — this silently defeated BOTH gating-milestone locks in `phase-attest.sh` (a `requesting-code-review` attestation actually recorded). Use `case " $LIST " in *" $item "*)`. All three fail **open and silent**. PAIRED: when touching a model-sourced lib, assert its contracts in every shell (bash/zsh/sh/dash) with the bash leg kept as an explicit control, and derive per-shell expectations from a separate capability probe rather than hardcoded shell names (dash has no self-location, so its correct behavior is *degradation*, not success). Regression: `tests/test-phase-attest-shell-portability.sh`. `phase-evidence.sh` shares the `BASH_SOURCE` pattern but is hook-only (`#!/bin/bash`), so it is unaffected — re-check that if it ever becomes model-sourced.
- Grepping runtime text output (CLI/log streams, not source — Serena/LSP don't apply): use `grep -F` (or `\[ERROR\]`) when matching literals containing regex metacharacters. `grep "[ERROR]"` is a character class matching any of `E,R,O` and silently returns wrong lines; `grep "v1.9.0"` matches `v1X9Y0` because `.` is a wildcard. Bites `incident-analysis` (log-level greps), `behavioral-evaluation` (version-string assertions), and any future runtime-output parser.
- `CLAUDE_PLUGIN_ROOT` from env; fallback: `$(cd "$(dirname "$0")/.." && pwd)`.
- `docs/plans/` is gitignored — use `git add -f` for design docs.
- When user says "proceed", continue with the next logical step. Do not ask "what would you like to proceed with?" — infer from context.
- `skills/incident-analysis/SKILL.md` has a word-count **ratchet**, not a fixed ceiling — `INCIDENT_SKILL_WORD_BASELINE` in `tests/test-incident-analysis-content.sh` is pinned to the file's exact current size, so headroom is deliberately ZERO and growth in either direction fails until the constant is edited. That visibility is the control; the number is not sacred. Growing it: extract tables, YAML schemas (>15 lines), URL templates and rationale to `references/` FIRST, then raise the constant in the same commit and say why in the message. Shrinking it: lower the constant in the same commit, or a staleness leg fails and the reduction is banked as new slack. This replaced a fixed 11,500 ceiling that had drifted to 66 words of headroom while never once forcing a reduction — do not restate that number as the limit, because it permitted regrowth up to the cap, which is a ratchet in the wrong direction.
- Memory backends are orthogonal: Forgetful MCP = cross-session architectural memory (opt-in), Claude Code auto-memory at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in, slug-indexed with typed frontmatter). Do not dual-write — pick one per learning based on whether it's cross-project (Forgetful) or project-local (auto-memory). See `skills/unified-context-stack/tiers/historical-truth.md` "Memory backend boundary".
- `.claude/knowledge/` writes are human-gated AND PR-gated (memory-poisoning / lethal-trifecta surface) — never auto-write; the session-start injection is framed as untrusted reference data; `scripts/knowledge-validate.sh` is the consistency gate (type present, no dangling `[[links]]`, index↔files match, source resolves).
- **`tests/run-tests.sh` self-guards stdin (`exec < /dev/null`, #142) — every OTHER invocation still must not (`< /dev/null` stays mandatory).** Hooks read their payload from stdin, and `session-start-hook.sh` does it behind `[ ! -t 0 ]` — **a TTY check is not an "input available" check**: a socket or FIFO is not a TTY, so `$(cat)` runs and blocks forever waiting for an EOF that never arrives. ~15 test call sites invoke that hook with no redirect and inherit fd 0, so before the runner guard a suite launched with socket stdin (routine in an agent session) parked mid-run at near-zero CPU with **no error** — one run idled ~2h, and it reads as "slow suite", not as a bug; the tell is `lsof -p <pid> -d 0` showing fd 0 on a socket. The runner guard is inherited by all 114 discovered files at once, but covers ONLY `run-tests.sh`: `bash tests/test-context.sh`, `bash hooks/session-start-hook.sh`, and any CI step invoked directly still hang without their own `< /dev/null` — which is why `.github/workflows/done-gates.yml` carries the redirect on every step with a comment calling it "REQUIRED, not decorative". The deeper `[ ! -t 0 ]` fix is deliberately NOT done (hardening a fail-open, gate-adjacent hook is a different risk class). Regression: `tests/test-suite-stdin-guard.sh`, which drives a copy of the real runner over a FIFO under an inline watchdog (macOS has no `timeout(1)`) and carries a red control so it cannot go vacuous. PAIRED: that control must assert the strip **changed** something (`cmp -s`) — asserting only "the guard pattern is absent from the stripped copy" is equally true when the strip worked and when the pattern never matched, so it passed with the guard deleted from main until review mutation-tested it.
- **A suite log is COMPLETE only if it says so — `tests/run-tests.sh` now emits a sentinel, and nothing else may stand in for it (#263).** The runner's terminal block (`Files run:` / `Files passed:` / `Files failed:` inside a `====` frame) is **shape-identical** to the block `tests/test-helpers.sh::print_summary` emits at the end of EVERY individual test file (`Tests run:` …, same four-space padding, same frame) — one word apart. So a reader that lands on a per-file block, tailing a running log or reading one reaped partway, cannot tell it from the runner's own end. Completion was therefore assertable only by ABSENCE, and **nothing in the repo asserted it** (measured: zero consumers of `Files run:` outside the runner). Measured 2026-08-27 on a real reaped run: **91 of 122 files executed, thousands of PASS assertions, zero `FAIL:` lines** — every signal a normal check inspects said green, and the failure direction is CLEAN, which CI goes green on. Two shapes produce it: `nohup … &` inside a backgrounded Bash call (reaped with its parent's process group) and the harness auto-backgrounding any call over ~120s (this suite is ~13 min), after which the result is never handed back. **The rule: gate a pass claim on the sentinel's PRESENCE, never on the absence of `FAIL:` lines** — the latter is equally true of a suite that never started. `scripts/assert-suite-complete.sh <log>` is the supported reader and has **four** outcomes, never two: `0` complete+pass (the only state licensing the claim), `1` complete-but-not-a-pass (truncated, **vacuous — a run over 0 files is not green**, or malformed), `2` complete+FAILED, `3` **cannot check** (no argument, missing, unreadable, whitespace-only). `3` is separate from `1` deliberately: a checker that reports clean when it could not parse its input is worse than no checker. PAIRED: `verify-and-record.sh` is UNAFFECTED — it waits on the command and keys PASS to exit 0, which is correct; the defect only ever hit readers of a log. The portable half of the rule (never key a pass claim on absent failure markers; if the runner has no completion marker, re-run it synchronously) is in `skills/project-verification/SKILL.md`, because the sentinel itself is this repo's runner and cannot be assumed in an installer's repo. **KNOWN LIMIT, do not overstate it:** the sentinel is a CONVENTION enforced by a source grep, not a property. A test file printing the literal string as its own last line, in a run reaped at exactly that instant, reads as complete — pinned as an explicit `KNOWN LIMIT` cell rather than papered over. What IS a property: a suite that runs to its end then carries TWO sentinels, and two are rejected. `--min-files N` covers the other way a suite fails to run in full — the sentinel proves the runner reached its END, not that its glob DISCOVERED everything, so a partial checkout yields a smaller, well-formed, entirely green run. **Nothing invokes the checker automatically**, and that is inherent: the synchronous path is already correct via the exit code, and the defect only reaches a human or agent *reading a log*, whom no gate can compel. It is in the Commands table so it is findable. Regression: `tests/test-suite-completion.sh` — fixture logs are produced by the REAL runner copied verbatim and then cut, never hand-written (a hand-written fixture only proves the checker agrees with the test's own idea of the format; the two negative fixtures, an empty and an unstructured log, are necessarily synthetic). It carries a mutation cell that removes the feature (function AND call sites, not just the printf — stripping the printf alone leaves a broken runner, which is a different counterfactual) and a paired end-to-end cell asserting the truncated log has **zero** `FAIL:` lines **and** is still reported incomplete — asserting only the second half would pass even if the naive check already caught it. Review added six cells for branches no cell reached: mutating the unrecognised-status arm to exit 0 left the file 25/25 green. **The Critical it missed is the transferable one:** `case ''|*[!0-9]*` admitted counts that `[ -ne ]` and `$(( ))` then FAILED to evaluate — past `INT64_MAX`, or a leading-zero octal trap like `08` — and with no `set -e` the failing comparison printed to stderr and execution fell THROUGH to the `status=pass` branch and `exit 0`. A validator that accepts what the later arithmetic cannot evaluate turns a parse failure into a clean pass, which is exactly the thing the script exists to forbid; `_is_count` now bounds the length and rejects leading zeros so the arithmetic is total. And `sentinel-not-last` was satisfied by the FALLBACK path — the appended junk line tripped the malformed-fields branch instead, so the cell passed with the whole last-line check deleted; its trailing line must itself PARSE.

### Path-scoped rule files

The rest of this section lives in `.claude/rules/*.md`, each scoped with `paths:`
frontmatter so it loads when you touch the files it governs rather than every
session. The prose is verbatim — nothing was summarised in the move.

**The filing criterion is whether the guidance needs a file open, NOT its subject
matter.** A bullet governing your own shell, your own tool calls, or how you read
command output has no triggering file and therefore stays HERE — that is why the
zsh, `grep -F`, stdin-guard and suite-sentinel bullets above are in this file even
though they are "about" tests and shell. Filing those four by topic was the first
mistake this split made; four of thirty were misfiled that way. When adding a
bullet, ask what would have to be open for it to load, and if the answer is
"nothing in particular", it belongs above.

A bullet that merely *mentions* a file in passing is deliberately NOT globbed onto
it — only the surfaces a bullet governs. In particular `push-gate-enforcement.md`
does not glob `config/*.json`: those preconditions are `remedy-reachability.md`'s
subject, and re-adding them here would pull 62k into the ~85% of commits that touch
config, which is the cost this split exists to avoid.

**If you are reasoning about one of these surfaces without opening a file that
triggers the rule, read the file directly**; a path-scoped rule does not load on
reasoning alone, and does not come back after `/compact` until a matching file is
read.

| Rule file | Governs | Read it before |
|---|---|---|
| `push-gate-enforcement.md` | `openspec-guard.sh`, `skill-gate.sh`, `publish-guard.sh`, the gate libs (`verdict`, `git-command`, `branch-ledger`, `phase-*`), `gate-status.sh` | touching any deny leg, subject resolution, command parsing, deny text, or fail-open announcement |
| `remedy-reachability.md` | the `config/*.json` preconditions, `skill-activation-hook.sh` rendering, `phase-attest.sh`, `assets/design-seed/` | changing any text that tells an agent how to fix a block, or any path a rendered hint names |
| `push-gate-telemetry.md` | `implement-shadow.sh`, `review-shadow.sh`, `shadow-corpus.sh`, `pr-diff.sh`, `shadow-adjudicate.sh`, `push-gate-capture.sh` | touching a shadow corpus, a `predicate_version`/`schema_version`, or any pre-registered rate |
| `outbound-guards.md` | `publish-guard.sh`, the egress-consent hooks, `consult-dispatch.sh`, `reviewer-evidence-hook.sh` | changing what may leave the machine, or how reviewer dispatch is credited |
| `test-suite.md` | `tests/**`, `.github/workflows/**`, `.verify.yml`, `improvement-miner/` | adding or changing a test, a fixture gate, or a CI workflow |
| `shell-portability.md` | every `*.sh` under `hooks/`, `scripts/`, `tests/`, `skills/` | writing shell that a hook or a test will run under bash 3.2 |
| `routing-state.md` | `skill-activation-hook.sh`, `session-start-hook.sh`, `config/*.json`, `persist-state.sh` | changing routing, scoring, session tokens, or composition state |

`docs/enforcement-map.md` is the one-page map of everything that can block, in
check order; `bash scripts/gate-status.sh` replays those checks against the
current branch. Start there for "why was this denied", not with the rule files.

## Spec Persistence Modes

Two modes for where design intent is persisted:

**Default (`docs/plans/`-first):** Design docs, plans, and specs go to `docs/plans/*.md` (gitignored). Low-ceremony, session-scoped. Best for solo dev or exploratory work. `openspec-ship` creates retrospective `openspec/changes/` at SHIP time.

**Spec-driven mode (`openspec/changes/`-first):** Set `{"preset": "spec-driven"}` in `~/.claude/skill-config.json`. Design intent is committed to `openspec/changes/<feature>/proposal.md + design.md + specs/<cap>/spec.md` during DESIGN phase. Teammates see in-progress specs via `git pull`. `openspec-ship` syncs the existing change at SHIP time instead of creating from scratch.

**When to use spec-driven:**
- ≥2 active developers on the repo
- Long-lived codebase where decision traceability matters
- Teams with concurrent work on overlapping capabilities
- Repos planning to add `openspec validate` to CI

**When to stay default:**
- Solo development
- Short-lived repos / prototypes
- Exploratory phases where designs frequently get rejected
- Repos without an established capability taxonomy

**Task plans stay local in both modes.** `docs/plans/*-plan.md` (task breakdowns, checkbox progress) is unchanged by the mode flag — those are the dev's execution scratch.

**Switching modes:** Change the preset at any time; existing artifacts are not migrated. New features use the new location.

**CI enforcement:** Spec-driven mode pairs with the `OpenSpec Validate` GitHub Actions workflow (`.github/workflows/openspec-validate.yml`). The workflow runs `scripts/validate-active-openspec-changes.sh` on every PR. For true hard-block enforcement, the check must be marked **Required** in GitHub Branch Protection — see `docs/CI.md` for setup steps.

**Per-capability review routing:** Pair spec-driven + CI with `.github/CODEOWNERS` to auto-route reviews per capability. Copy `.github/CODEOWNERS.template` into your repo and replace the `@your-*-team` placeholders with real teams. Full guide in `docs/CI.md`.
