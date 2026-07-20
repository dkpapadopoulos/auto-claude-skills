# memory-validate sweep — design

**Status:** approved (brainstorming), pending plan
**Date:** 2026-07-20
**Author:** improvement-miner run 2026-07-19 → normal chain
**Evidence:** improvement-miner issue #125 (rejected-STALE) — a memory proposed changing a phrase deleted from the repo ~2 months earlier; the miner trusted a stale memory. See memory `self-improvement-factory` ("Miner gap confirmed … staleness check missing").

## Problem

Claude Code auto-memory (`~/.claude/projects/<project>/memory/`) drifts silently: a memory written when true keeps citing repo artifacts (files, paths) that later move or vanish. There is no consistency gate for the memory store, unlike `.claude/knowledge/` which has `scripts/knowledge-validate.sh`. The concrete cost surfaced when improvement-miner mined a stale section and produced a dead proposal (#125).

Best-practices literature (STALE, arXiv:2605.06527; memory-architectures survey, arXiv:2603.07670) confirms fuzzy staleness *reasoning* is unreliable (best models ~55%), and the hardest class is "Implicit Conflict" — a later fact silently invalidates an earlier memory. Conclusion: ship a **narrow, deterministic, high-precision** check (does a cited repo path still exist at HEAD?) and leave fuzzy judgment to the human gate.

## Non-goals (v1)

- Superseded/age signals (revival-date-passed, PR-open-but-merged). Cut: needs network/GitHub state + prose interpretation, largest false-positive blast radius. **Revival criterion:** a real instance where an age/PR-state signal would have caught a stale memory that the anchor check missed, ≥1–2×.
- Rewriting or auto-updating memories. This is a read-only validator; humans fix.
- Line-number validity of `path:NN` anchors — too brittle against edits; we check file existence only.

## Audience & shape

Generic plugin script `scripts/memory-validate.sh <memory-dir> [repo-root]`, Bash 3.2 compatible, modeled on `scripts/knowledge-validate.sh`. Any project using auto-memory can run it; this repo is the first consumer. `repo-root` defaults to `$PWD` (or `git rev-parse --show-toplevel`); anchors resolve against that repo's HEAD.

## Posture: advisory-first, two-tier exit

- **Not CI-blocking in v1.** Run manually or as an improvement-miner bundle input. The memory store is prose; a false block on historical context costs more than a missed warning.
- **Two-tier exit contract:**
  - **ERROR (exit 1)** — structural defects (unambiguous, mirrors knowledge-validate.sh).
  - **WARN (exit 0)** — staleness (dangling repo-path anchors). Printed to stderr, never changes exit code.
- This keeps the door open to wiring it somewhere later without a fuzzy check ever being able to block.

## Checks

**Tiering principle (re-calibrated during REVIEW against the real 141-file store, user-approved):** corruption ⇒ ERROR (exit 1); drift and blessed-forward-references ⇒ WARN (exit 0). See As-Built Calibration below for why this differs from the first draft.

### ERROR tier (corruption)
1. **Frontmatter type** — every non-`MEMORY.md` `.md` has a valid type ∈ `{feedback, project, reference, user}`. The store has **two schema variants**: top-level `type:` (42 files) and nested `metadata.type:` (99 files); the extractor accepts either (nested preferred).
2. **Reverse index sync** — every `MEMORY.md` `(<file>.md)` link points at an existing file (a dead index link is corruption).

### WARN tier (drift / stale — advisory, exit stays 0)
3. **Forward index sync** — a memory file absent from `MEMORY.md` (drift; may be a new or intentionally-unlisted memory).
4. **Dangling `[[name]]` links** — a `[[name]]` resolving to no memory. Auto-memory explicitly blesses forward-references ("marks something worth writing later, not an error"), so WARN not ERROR. Resolution accepts the store's **four interchangeable link conventions**: frontmatter `name:` slug; bare filename (underscores); filename underscores→hyphens; prefix-stripped (`feedback_`/`project_`/`reference_` removed) in underscore and hyphen forms.
5. **Dangling repo-path anchors** — backtick-wrapped `` `path.ext` `` / `` `path.ext:line` `` references that do NOT resolve at repo HEAD → WARN.
   - Resolve against `git -C <repo-root> ls-tree -r --name-only HEAD` (HEAD, not working tree — gitignored `docs/plans/` and uncommitted edits must not mask staleness).
   - **Skip fenced code blocks** (``` ``` toggles) before extraction.
   - **Ext allowlist** for the path shape: `sh|md|json|yml|yaml|txt|ts|js|py`.
   - Strip `:NN` line suffix before resolution.
   - **Basename resolution** for bare-basename and absolute-path anchors (memories cite `openspec-guard.sh` for `hooks/openspec-guard.sh`, or absolute `/Users/.../CLAUDE.md`) — resolves if any HEAD file has that basename.
   - **Suffix match** for partial-path anchors (`specs/skill-routing/spec.md` matches `openspec/specs/skill-routing/spec.md`).
   - **Skip cross-memory-file references** — a backtick ref to a sibling `.md` memory belongs to the `[[link]]` namespace, not repo anchors.
   - **Working-tree NOTE:** a path absent at HEAD but present on disk → advisory NOTE, not a staleness WARN.

## Anchor extraction & Bash 3.2 notes

- Strip fenced blocks with an `awk` toggle, then `grep -oE` backtick-wrapped path-shaped tokens against the ext allowlist.
- Dedup with newline-delimited temp files + `sort -u`. No associative arrays, no `mapfile`, no `for x in $(...)` unquoted word-splitting on paths with spaces (memory paths have none, but guard anyway).
- Literal matching uses `grep -F` where the needle contains regex metacharacters (paths contain `.`), per the runtime-output-grep gotcha.
- Follows the CLAUDE.md fail-open / Bash-3.2 arithmetic rules.

## Testing

`tests/test-memory-validate.sh` — hermetic (builds a throwaway git repo + memory fixtures; no dependence on the real store or its HEAD). 12 assertions:
- **ERROR:** missing type → exit 1; reverse index ghost → exit 1.
- **WARN (exit 0):** dangling `[[link]]` (resolvable link stays silent); unindexed file; stale anchor (reproduces #125); bare-basename absent at HEAD.
- **No-false-positive (silent):** both type schema variants accepted; live anchor with `:line`; bare basename of a nested HEAD file; absolute path whose basename is at HEAD; fenced-block anchor ignored.
- **NOTE:** working-tree-only path.
- Auto-discovered by `tests/run-tests.sh` (globs `test-*.sh`, no manual registration).
- Not a skill → skill routing-fixture/content-coverage gates do not apply.

## As-Built Calibration (REVIEW-phase, 2026-07-20)

The Task-4 smoke run against the real 141-file store exposed that the first-draft ERROR tiering was wrong for this store's actual semantics — it produced ~80 false ERRORs. Corrections (all user-approved re-tiering + evidence-driven bug fixes):
- **Type extraction** accepted only nested `metadata.type`; the store has 42 top-level + 99 nested + 1 genuinely missing. Fixed to accept both → 1 real ERROR.
- **`[[link]]` resolution** assumed slug==filename; the store links by four interchangeable conventions (see check 4). Fixed → dangling-link WARNs 111 → 7, all genuine. Downgraded ERROR→WARN (spec blesses forward-refs).
- **Anchor resolution** used root-only `git cat-file`; memories cite bare basenames, partial paths, absolute paths, and sibling memory files. Fixed with basename/suffix/absolute resolution + cross-memory skip → stale-anchor WARNs 130 → 29 (remaining are genuine relocations/deletions).
- **Index sync** split: reverse (dead index link) = ERROR; forward (unindexed file, 20 on the store) = WARN.

Final real-store output: **1 ERROR + 56 WARN** (7 dangling + 29 stale-anchor + 20 unindexed), all defensible. Lesson: prose path/link intent is not structurally knowable (codex (a)); calibration against the real store, not fixtures alone, was load-bearing.

## Integration (future, out of scope for this change)

improvement-miner Step-1 bundle could invoke `memory-validate.sh` and surface per-memory staleness alongside the evidence — deferred to issue #138's implementation (miner-side staleness gate). This change ships the primitive only.

## Sparring record

Codex (repo-grounded, bounded) drove five load-bearing corrections, all adopted: anchors WARN-only vs structural ERROR; skip fenced blocks / ext-allowlist to kill false positives; resolve at HEAD not working tree; working-tree-only advisory note; cut check-4 superseded/age from v1. Best-practices web check (STALE, memory-survey) independently supported the "narrow deterministic over fuzzy" call.
