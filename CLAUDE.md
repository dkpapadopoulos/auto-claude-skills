# auto-claude-skills

Claude Code plugin for automatic skill routing based on prompt intent and SDLC phase.

## Commands

| Command | Description |
|---------|-------------|
| `bash tests/run-tests.sh` | Run all test suites |
| `bash scripts/assert-suite-complete.sh [--min-files N] <log>` | Decide whether a suite LOG represents a run that finished (0 complete+pass, 1 not-a-pass, 2 complete+failed, 3 cannot-check) |
| `bash scripts/verify-shadow-adjudicate.sh` | Read the VERIFY measured-verdict shadow corpus against its pre-registered decision rule (#301; owner reviews fortnightly from 2026-10-12) |
| `bash tests/test-routing.sh < /dev/null` | Test skill routing engine |
| `bash tests/test-registry.sh < /dev/null` | Test registry building and merging |
| `bash tests/test-context.sh < /dev/null` | Test context formatting and phase composition |
| `bash scripts/keyword-path-audit.sh < /dev/null` | Measure what the routing hook's keyword path admits, against the recorded decisions (0 agrees, 1 findings, 3 cannot-check; #310) |
| `bash scripts/compaction-pairing.sh` | Per-month compactions vs recoveries and any compaction with none (0 paired, 1 unpaired or unrecognised line, 3 cannot-check); three consecutive months of `carrier=0` with zero pending retires the prompt carrier |
| `bash -n hooks/<name>.sh` | Syntax-check a hook (no execution) |
| `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh < /dev/null` | Debug routing with explanation output |

## Architecture

- **Two main hooks**: `session-start-hook.sh` builds the skill registry at session start; `skill-activation-hook.sh` scores and routes on every prompt.
- **Registry**: Cached at `~/.claude/.skill-registry-cache.json`. Merged from `config/default-triggers.json` + plugin discoveries + `~/.claude/skill-config.json` overrides.
- **Scoring**: Regex trigger match, or a keyword substring match on its own → base score + priority + name bonus + composition bonus → role-cap selection (max 1 process, 2 domain, 1 workflow).
- **Output**: JSON via `hookSpecificOutput` on stdout. Hooks fail-open (exit 0 on error).

## Skill-creation flow

Three-stage division of labor for building new skills:

1. **`writing-skills`** (DESIGN phase, `role=required`, always fires) — enforces discipline, anatomy completeness, and a failing pressure-test before a line of implementation is written.
2. **`skill-scaffold`** — emits seed files including the routing fixture stub (`tests/fixtures/routing/<name>.txt`) and an evals stub; provides the mechanical skeleton for the next two stages.
3. **`skill-creator`** (REVIEW phase, advisory) — validates triggering on a held-out prompt set before merge; catches over/under-matching that unit tests miss.

The **enforceable done-gate** is owned and deterministic and covers two artifacts per owned, trigger-routed skill: a routing fixture `tests/fixtures/routing/<name>.txt` with >=1 `MATCH` line and >=1 verbatim-borrowed `NO_MATCH` decoy (`tests/test-fixture-coverage.sh`), and a content-assertion test, meaning some `tests/*.sh` that references `skills/<name>/` (`tests/test-skill-content-coverage.sh`). Both run in CI via `.github/workflows/done-gates.yml` (blocking only once marked Required, see `docs/CI.md`; pinned by `tests/test-done-gate-ci.sh`). **`.verify.yml` is the LOCAL gate** (`substrate: local`, read by the push gate and `project-verification`), so the full `tests/run-tests.sh` suite is NOT a CI check. `writing-skills` and `skill-creator` are quality layers, not merge preconditions.

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
- Hook latency targets: session-start 200 ms; the activation hook, which runs on every prompt, ~50 ms. Measured 2026-10-12: ~1.6 s (twelve plugins); 172 ms median, 178 ms on a chained render, so treat both as targets, not facts. Minimize jq forks — batch into single calls.
- Field separator: `\x1f` (US). Intra-field delimiter: `\x01` (SOH). Never `\n` inside fields.
- Commit messages: `<type>: <description>` (fix, feat, docs, test, refactor).
- When editing files, never replace full content if only a section needs changing. Preserve existing data in YAML/JSON files. Use targeted edits, not full-file rewrites.

## Gotchas

- **The model's Bash tool is NOT bash — it is the user's shell (zsh 5.9 on macOS), while the whole test suite runs under bash**, so zsh-only breakage in anything the model runs (every ad-hoc command, and any lib it `source`s) passes every gate and fails silently for real users. zsh DOES split unquoted command substitution (`for f in $(git …)` is safe) but NOT an unquoted scalar: `V="a b c"; for x in $V` runs once and `set -- $V` leaves `$#=1`, both exit 0, and the only tell is an impossibly clean result. Write lists literally, pipe them through `printf '%s\n' … | while IFS= read -r`, or use an array. A lib the model `source`s has three more zsh traps, stated in `.claude/rules/shell-portability.md` (regression: `tests/test-phase-attest-shell-portability.sh`).
- Grepping runtime text output (CLI and log streams, not source): use `grep -F` (or escape, `\[ERROR\]`) for literals containing regex metacharacters. `grep "[ERROR]"` is a character class and `grep "v1.9.0"` matches `v1X9Y0`, both silently.
- `CLAUDE_PLUGIN_ROOT` from env; fallback: `$(cd "$(dirname "$0")/.." && pwd)`.
- `docs/plans/` is gitignored — use `git add -f` for design docs.
- When user says "proceed", continue with the next logical step. Do not ask "what would you like to proceed with?" — infer from context.
- `skills/incident-analysis/SKILL.md` has a word-count **ratchet**, not a ceiling: `INCIDENT_SKILL_WORD_BASELINE` in `tests/test-incident-analysis-content.sh` is pinned to the file's size, so any growth fails until the constant is raised. Extract tables, YAML schemas (>15 lines), URL templates and rationale to `references/` first; if it still grows, raise the constant in the same commit and say why. When you shrink it, lower the constant in the same commit: a cut of 250 or more words fails, and a smaller one passes and is banked as slack. Never restate the old fixed 11,500 ceiling as the limit.
- Memory backends are orthogonal: Forgetful MCP = cross-session architectural memory (opt-in), Claude Code auto-memory at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in, slug-indexed with typed frontmatter). Do not dual-write — pick one per learning based on whether it's cross-project (Forgetful) or project-local (auto-memory). See `skills/unified-context-stack/tiers/historical-truth.md` "Memory backend boundary".
- `.claude/knowledge/` writes are human-gated AND PR-gated (memory-poisoning / lethal-trifecta surface) — never auto-write; the session-start injection is framed as untrusted reference data; `scripts/knowledge-validate.sh` is the consistency gate (type present, no dangling `[[links]]`, index↔files match, source resolves).
- **`tests/run-tests.sh` self-guards stdin (`exec < /dev/null`, #142) — every OTHER invocation still must not (`< /dev/null` stays mandatory).** `session-start-hook.sh` reads stdin behind `[ ! -t 0 ]`, which is not an "input available" check: with socket or FIFO stdin (routine in an agent session) `$(cat)` blocks until an EOF that may never come, with no error, and reads as a slow suite (tell: `lsof -p <pid> -d 0` shows a socket). So `bash tests/test-*.sh`, `bash hooks/*.sh` and any directly invoked CI step need their own redirect. The hook's `[ ! -t 0 ]` is deliberately left alone (hardening a fail-open, gate-adjacent hook is a different risk class). Regression: `tests/test-suite-stdin-guard.sh`; CI step redirects are pinned by `tests/test-done-gate-ci.sh`.
- **A suite log is COMPLETE only if it says so — `tests/run-tests.sh` emits a sentinel, and nothing else may stand in for it (#263).** Gate any pass claim on the sentinel's PRESENCE, never on the absence of `FAIL:` lines: a reaped or truncated run has none either (measured: 91 of 122 files run, zero `FAIL:` lines), and every test file ends in a `Tests run:` block shape-identical to the runner's `Files run:` block. Two shapes truncate silently: `nohup … &` inside a backgrounded Bash call, and the harness auto-backgrounding any call over ~120 s (the suite takes ~13 min). Read a log with `scripts/assert-suite-complete.sh [--min-files N] <log>`; only exit `0` licenses a pass claim (`1` truncated, vacuous over 0 files, or malformed; `2` complete and failed; `3` cannot check). `--min-files` covers partial discovery, which the sentinel cannot see. Known limit: the sentinel is a convention, so a test file printing it and a runner frame as its last lines, in a run reaped at that instant, reads as complete. A synchronous run is already correct via its exit code. The portable half of this rule, for repos without this runner, is in `skills/project-verification/SKILL.md`; keep both in step. Regression: `tests/test-suite-completion.sh`.

### Obligations that no rule file can deliver

**Which actions load a path-scoped rule depends on the Claude Code version.** Measured
2026-09-27 on CLI 2.1.274: the `Read` tool ONLY — not Bash `cat`/`sed`/`grep`, not
`Write`; `Edit` delivered only because it requires a prior `Read`. Serena's readers
loaded nothing (2026-09-28, version unrecorded; positive control on the identical file:
`Read` loaded the rule). Since then the changelog says 2.1.288 loads rules when `Write`
or `Edit` creates or changes a file in scope, and 2.1.293 on a single-file Bash
`cat`/`head`/`tail`/`sed -n`/`grep`. Live probes, one trial each: a lone `sed -n` read
loaded the rule on 2.1.304 (2026-10-23) and on 2.1.308; a compound read loaded none on
2.1.304 (`…; true`) but did load on 2.1.308 (`…; true` and `cd … && …`); a piped read (`… | cat`)
loaded none on either. Serena and the `Write`/`Edit` change were not re-probed.
Two consequences, and both are why the list below is HERE rather than in a rule file.

**(1) Read a governed file before editing it.** Before changing anything under
`hooks/`, `config/`, `scripts/`, `tests/` or `skills/`, open it with `Read` — the one
action that loaded its rule in every probe so far, and the one the changelog never
narrowed. Which Bash reads deliver varies by version (above), and that editing via
`sed -i`, a heredoc or a script delivers none was inferred on 2.1.274 from the Bash-read
result, never measured. This deliberately overrides the general
preference for Bash reads, for these paths only. Same for Serena: its symbol tools are
right for *finding* things and deliver no rule, so Read the file before you change it.

**(2) These six obligations fire when you ADD something, so there is no file to Read
and no rule can reach you.** Each is stated in full in the rule file named:

- A new gate-**enforcement** lib MUST be added to `_GATE_ENFORCE_LIBS` — it feeds both
  the session-start canary and the drift manifest. (`push-gate-enforcement.md`)
- A new guard-sourced gate lib MUST get a `_DEGRADED_MSG` note, or its fall-open is
  silent (#198). Two such libs each remove a *deny*. (`push-gate-enforcement.md`)
- Any future helper that wraps a `source` MUST be added to the #137 lint matcher, or
  that lint's population silently drops. (`push-gate-enforcement.md`)
- Any new caller iterating `_gc_split_segments` MUST use `IFS="${_GC_SEP}"` (#155).
  (`push-gate-enforcement.md`)
- A third caller of the merge-advisory rule MUST call `_advisory_text_for_action`
  rather than re-derive it — re-derivation is how #166 diverged. (`push-gate-enforcement.md`)
- A new shadow leg MUST use `hooks/lib/shadow-corpus.sh` rather than re-derive the band
  rule, episode grouping or the ISO prelude. (`push-gate-telemetry.md`)

### Path-scoped rule files

The rest of this section lives in `.claude/rules/*.md`, each scoped with `paths:`
frontmatter so it loads when you touch the files it governs rather than every
session.

**File a bullet by whether following it needs a file open, NOT by its subject.**
Guidance about your own shell, your tool calls, or how you read command output has
no triggering file and belongs here (hence the zsh, `grep -F`, stdin and sentinel
bullets above, pinned here by LEG 5 of `tests/test-claude-md-rule-split.sh`). Glob a
rule only onto the surfaces its bullets govern, never onto files they merely
mention: `push-gate-enforcement.md` does not glob `config/*.json`, which most
commits touch.

**If you are reasoning about one of these surfaces without opening a file that
triggers the rule, read the file directly**; a path-scoped rule does not load on
reasoning alone, and does not come back after `/compact` until a matching file is
read.

| Rule file | Governs | Read it before |
|---|---|---|
| `push-gate-enforcement.md` | `openspec-guard.sh`, `skill-gate.sh`, `publish-guard.sh`, the gate libs (`verdict`, `git-command`, `branch-ledger`, `phase-*`), `gate-status.sh` | touching any deny leg, subject resolution, command parsing, deny text, or fail-open announcement |
| `remedy-reachability.md` | the `config/*.json` preconditions, `skill-activation-hook.sh` rendering, `phase-attest.sh`, `assets/design-seed/` | changing any text that tells an agent how to fix a block, or any path a rendered hint names |
| `push-gate-telemetry.md` | `implement-shadow.sh`, `review-shadow.sh`, `verify-shadow.sh`, `shadow-corpus.sh`, `pr-diff.sh`, `shadow-adjudicate.sh`, `push-gate-capture.sh` | touching a shadow corpus, a `predicate_version`/`schema_version`, or any pre-registered rate |
| `outbound-guards.md` | `publish-guard.sh`, the egress-consent hooks, `consult-dispatch.sh`, `reviewer-evidence-hook.sh` | changing what may leave the machine, or how reviewer dispatch is credited |
| `test-suite.md` | `tests/**`, `.github/workflows/**`, `.verify.yml`, `improvement-miner/` | adding or changing a test, a fixture gate, or a CI workflow |
| `shell-portability.md` | every `*.sh` under `hooks/`, `scripts/`, `tests/`, `skills/` | writing shell that a hook or a test will run under bash 3.2, or changing what a shared shell function promises |
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
