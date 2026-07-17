# Design: add-scope-conformance-check

## Context

worklease (third-party, rejected as dependency: Node >=18 vs bash-3.2
doctrine) demonstrates a post-hoc conformance score: did each agent's merged
changes fall inside its declared claim? We adopt only that primitive. The
superpowers `writing-plans` template already mandates per-task `**Files:**`
blocks with exact paths — the declared-scope artifact already exists on the
common path; nothing upstream needs to change.

## Capabilities Affected

- scope-conformance (ADDED): deterministic declared-vs-actual file-scope check.
- implementation-drift-check (integration): new deterministic pre-pass.
- agent-team-execution (integration): completion/review-time scope step.

## Decisions

1. Tri-state verdict, advisory: `clean` (exit 0) | `violation` (exit 1) |
   `unverified` (exit 2). Missing/unparseable plan degrades to `unverified`,
   never `clean` and never a block.
2. Manifest source = the plan's existing `- Create:/Modify:/Test:/Delete:`
   backticked entries plus an optional `- Allow:` glob extension. Line-range
   suffixes (`path.py:123-145`) are stripped.
3. Matching: exact path or bash `case` glob (patterns are conservative-
   inclusive: `*` in a case pattern crosses `/`). Built-in meta allowlist for
   chain artifacts every feature touches: `docs/plans/*`, `openspec/*`,
   `CHANGELOG.md`.
4. Base resolution: explicit arg, else merge-base with the first of
   origin/main, main, origin/master, master.
5. Changed-set = `git diff --name-only <base>` (committed + uncommitted,
   includes deletes) plus untracked files (`git ls-files --others
   --exclude-standard`).
6. Branch-level attribution only. Per-specialist attribution in a shared
   workspace is NOT deterministic (a global diff is not "this specialist's
   diff"); agent-team integration is labeled team/branch-level.

## Out-of-Scope

- Push-gate enforcement (`hooks/openspec-guard.sh`) — advisory first; a gate
  is only justified once the manifest format is reliably present.
- Cross-session claim registry, TTL leases, PreToolUse claim checks
  (parked with revival criteria: proven multi-session intent-collision pain
  despite worktrees, or a major harness adopting a claims format natively).
- Per-specialist write attribution.
- `openspec/changes/*/tasks.md` as a secondary manifest source (follow-up).
- Modifying any superpowers skill.

## Acceptance Scenarios

1. GIVEN a plan declaring `scripts/foo.sh` and a branch that only changed
   `scripts/foo.sh`, WHEN the script runs, THEN it prints a clean verdict and
   exits 0.
2. GIVEN a plan declaring `scripts/foo.sh` and a branch that also changed
   `hooks/bar.sh`, WHEN the script runs, THEN it lists `hooks/bar.sh` as an
   out-of-scope file and exits 1.
3. GIVEN no readable plan file (or a plan with no parseable Files entries),
   WHEN the script runs, THEN it reports `unverified` and exits 2.
4. GIVEN a plan entry `` `src/api.py:12-40` ``, WHEN parsed, THEN the
   manifest entry is `src/api.py` (range stripped).
5. GIVEN a plan entry `` - Allow: `tests/*` `` and a changed untracked file
   `tests/test-new.sh`, WHEN the script runs, THEN the file is covered.
6. GIVEN an out-of-scope DELETED file, WHEN the script runs, THEN the
   deletion is reported as a violation (the recorded real incident class).

## Implementation Notes (synced at ship time)

- Plan-file self-exemption added: the manifest artifact itself is always
  in-scope (`PLAN_REL`), so a plan outside `docs/plans/` doesn't self-violate.
- Design decision 4 amended by review: ANY base (explicit or auto-resolved) is
  merge-base-normalized against HEAD — an explicit `main` on a diverged
  mainline false-violated in the reviewer's probe (red-validated pre-fix).
- `core.quotePath=false` on both git listings (non-ASCII filenames).
- Trailing-`/` directory entries normalize to `dir/*` (definitional fix
  preferred over documenting the gap).
- Drift-check exit-0 report row instructs flagging over-broad `Allow:` globs
  (e.g. bare `*`) instead of reporting a meaningless clean.
- Dogfooded on its own branch: first run caught a genuine under-declaration
  (`config/fallback-registry.json` from a conditional mirror step).
