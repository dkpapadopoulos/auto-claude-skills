# Design: merge-path PR-diff subject (#161)

## Architecture

### `hooks/lib/pr-diff.sh` (new, advisory-path only)

Two functions, both fail-open, both silent on stdout except their return value:

```
pr_ref_from_command <command>   -> echoes a bare PR number, or nothing
pr_changed_files <ref> <repo>   -> echoes newline-separated paths, or nothing
```

**`pr_ref_from_command`** recognises the shapes the guard already detects as
merges (`hooks/lib/git-command.sh` `command_invokes_gh_merge`):

| command | ref |
|---|---|
| `gh pr merge 7 --squash` | `7` |
| `gh pr merge --squash 7` | `7` |
| `gh api repos/o/r/pulls/7/merge` | `7` |
| `gh pr merge` (bare) | none — v1 records this `unresolved`; see Out-of-Scope |
| `gh api graphql … mergePullRequest` | none — node id, not a number |

**Validation is a security boundary, not a nicety.** The command is
model-authored text. The extracted ref MUST match `^[0-9]+$`; anything else
yields nothing. Without this, a crafted command could inject `--repo other/org`
or a flag into the `gh` invocation. The ref is passed as a single argument,
never interpolated into a shell string.

**Bare `gh pr merge`** means "the current branch's PR". Resolving it would need
a second `gh pr view --json number` call (no ref argument, so no injection
surface) — v1 does NOT implement that call; `pr_ref_from_command` returns
empty for a bare `gh pr merge` and the record is `unresolved`. See
Out-of-Scope.

**`pr_changed_files`** runs `gh pr view <ref> --json files --jq '.files[].path'`
with a hard timeout. Any failure — `gh` absent, unauthenticated, offline,
unknown PR, timeout — returns nothing.

### Predicate split

The existing docs-exclusion loop is extracted so both callers share one rule:

```
_names_touch_material_source <newline-separated-paths>   # the rule
_diff_touches_material_source <repo>                     # push: _branch_diff_names
_pr_touches_material_source <ref> <repo>                 # merge: pr_changed_files
```

The exclusion set (`docs/*`, `openspec/*`, `*.md`) is unchanged and now lives in
exactly one place.

### `diff_base` on the record

| value | meaning |
|---|---|
| `pr:<n>` | merge, measured against the merged PR's real file list |
| `branch-local` | push, `merge-base(mainline,HEAD)..HEAD` — unchanged semantics |
| `unresolved` | merge, but the PR diff could not be fetched |

An `unresolved` record is still written: the event happened, and losing it
would bias the corpus toward hosts with working `gh`. It is excluded from any
rate until adjudicated, exactly like an unlabelled record.

### Advisory flush

`_flush_push_advisories` currently returns early unless `_gc_is_push`. It gains
merges **only** when `diff_base` resolved to a real PR:

```
push                      -> flush (unchanged)
merge + diff_base=pr:<n>  -> flush (new)
merge + unresolved        -> silent (today's behaviour, preserved)
```

The existing comment's reasoning is honoured rather than overridden: silence
stays wherever the subject is unknown.

### Version bump

`IMPLEMENT_SHADOW_PREDICATE_VERSION` 1 → 2. Merge records under v1 were measured
against a branch-local delta; v2 merge records are measured against the PR. They
describe different things and MUST NOT be pooled. This is the field's designed
purpose, exercised for the first time.

## Trade-offs

- **First network call in the guard.** Confined to the merge path, behind an
  advisory, timeout-bounded, and degrading to today's exact behaviour. The push
  path is untouched and stays fully local.
- **~620ms on merges.** Acceptable against a multi-second network operation;
  unacceptable on pushes, which is why the split is strict.
- **Bare `gh pr merge` records `unresolved` in v1.** It is the common
  interactive form, so this leaves a real hole in the corpus; resolving it via
  a second `gh pr view --json number` call is moved to Out-of-Scope rather than
  built speculatively.
- **`unresolved` records dilute the corpus.** Preferred over silently dropping
  events, which would bias toward well-configured hosts. They are excluded from
  rates, not from the log.

## Dissenting views

- **"Just un-gate the flush."** Rejected — it surfaces a message about the wrong
  diff. The suppression was protecting users, and #161's framing as a pure gap
  was incomplete.
- **"Drop merge coverage instead."** A real option: it is smaller and keeps the
  corpus provably clean. Rejected because the spec requires push-or-merge and
  merges are a genuine outbound path the deny would eventually govern; a corpus
  missing them under-samples the intervention population.
- **Unresolved:** whether a `graphql mergePullRequest` node id can be mapped to
  a number cheaply. v1 records those `unresolved`.

## Decisions

1. New advisory-only lib; NOT added to `_GATE_ENFORCE_LIBS` (matches
   `implement-shadow.sh` and `push-gate-capture.sh`).
2. PR ref validated as `^[0-9]+$` before reaching `gh` — a security boundary.
3. `unresolved` records are written, not dropped.
4. Advisory stays silent whenever the subject is unknown.
5. `predicate_version` bumped to 2; v1 and v2 records never pooled.
6. Push path byte-unchanged — asserted by test, not by intent.

## Out-of-Scope

- Any change to a `permissionDecision`, deny path, or the deny-flip itself.
- Adjudication tooling (C2) and the backtest reader (C3).
- The `<10%` threshold and the spec's wrong instrument reference (issue #160).
- Mapping GraphQL node ids to PR numbers.
- Backfilling or reinterpreting `predicate_version: 1` records.
- **Resolving bare `gh pr merge` via a second `gh pr view --json number`
  call.** Verified absent from v1: `pr_ref_from_command` returns empty for a
  bare `gh pr merge`, so it always records `unresolved`, never a false
  `pr:<n>`. A follow-up would add that call, validate the returned number the
  same way as an explicit ref, and stay within the same timeout budget as
  `pr_changed_files`.
