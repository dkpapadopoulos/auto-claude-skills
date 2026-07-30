# Design: closing the #174 gate's silent-failure paths

## Architecture

Two files change. No new component, no new dependency, no change to
`hooks/lib/git-command.sh`.

### 1. Shell expansion is unscannable by construction

The gate receives the command as a **literal string**, pre-expansion. A body
carried by `$(…)`, backticks, `${…}`, `<(…)`, or a bare `$VAR` therefore has no
private words present at scan time. This is not a parser gap to close — no
amount of parsing recovers text the shell has not produced yet.

The only honest response is to **announce that the body was not visible**:

```sh
case "${_COMMAND}" in
    *'$('*|*'`'*|*'${'*|*'<('*|*'$'[A-Za-z_]*)
        _UNCHECKED="… body may be shell-expanded at run time …" ;;
esac
```

Three deliberate choices:

- **Announce, never deny.** An expansion is evidence we could not look, not
  evidence of a leak. Denying would false-block every legitimate
  `--body "$(cat notes.md)"`.
- **Outside the `_N -eq 0` branch.** A command may resolve one `--body-file`
  *and* carry a second, expanded `--body`; the second is just as unchecked.
- **`*'$'[A-Za-z_]*` for the brace-less form.** `*'${'*` alone misses the common
  `"$BODY"`. A literal `$` not followed by an identifier character (prices,
  `$1` in prose) does not match, so ordinary bodies stay silent.

### 2. A pipeline ending in `sort` hides the leading `awk`'s status

```sh
shingle_files "$@" | awk … | sort … > "${TMP}/mem"     # $? is sort's
```

An unreadable corpus file makes awk fail; the pipeline still exits 0; the
shingle set is empty; empty is indistinguishable from "no shingles"; the
`[ -s hits ] || exit 0` guard then returns **0 = clean** on a body that was
never compared. Fixed with `PIPESTATUS[0]` on both pipelines → exit 3
(cannot-check), which the hook already announces.

Triggers are ordinary: restrictive mode, a dangling symlink, a file removed
between the glob and the read. The hook runs the engine three times per
publish, so exposure is tripled.

### 3. Never truncate a partially built exemption

```sh
… | xargs -0 awk … > "${TMP}/repo" || : > "${TMP}/repo"   # wipes on failure
```

One unreadable tracked path (an ordinary `rm` of a tracked file, or a sparse
checkout) made awk fail, which **truncated the exemption already built**.
`[ -s repo ]` was then false, the exemption was skipped entirely, and every
candidate became a LEAK — asserting a leak that does not exist, indistinguishable
from a true positive.

Fixed by appending to a pre-truncated file and treating an incomplete build as
exit 3. An exemption that cannot be built completely means we cannot classify;
that is cannot-check, never "deny".

### 4. Command substitution inside an assignment trips the ERR trap

```sh
_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
```

The substitution runs *inside* the assignment, so a failing `cd` makes the whole
assignment non-zero and the blanket `trap 'exit 0' ERR` fires **at that line** —
above all three announce branches below it. This is the one unguarded sibling of
the `|| _MEMPROBE=""` guard added in the #174 round for exactly this hazard.
Split into an `if` with an explicit `|| _ROOT=""`, letting the existing announced
`[ ! -f … ]` check handle the empty root.

## Trade-offs

- **Announcement noise vs. silent bypass.** The expansion check will fire on
  legitimate expanded bodies. Accepted: an advisory line is strictly better than
  a protection the author believes in but does not have. Measured against the
  real corpus, ordinary literal publications stay silent.
- **Exit 3 on an unbuildable exemption is stricter.** Running the engine outside
  a git repo now reports cannot-check rather than flagging everything. This
  *removes* a false-deny path; it adds no new deny.
- **S7/S8/S9 deferred.** Bundling performance work into a security fix would
  make the change harder to verify independently.

## Dissenting views

*"Match a bare `$` to be maximally safe."* Rejected: a literal `$` in a body
(prices, shell prose) is common, the body IS visible in that case, and announcing
"could not check" when we did check is a false statement that trains the reader
to ignore the warning.

*"Deny on shell expansion."* Rejected: it false-blocks the documented in-repo
idiom and would push authors toward disabling the hook — the failure mode that
ends with no gate at all.

## Decisions

1. Expansion → announce, never deny; checked outside the zero-files branch.
2. Both shingling pipelines and the exemption build → `PIPESTATUS` → exit 3.
3. Partial exemption → never truncated; incomplete → cannot-check.
4. `_ROOT` → split assignment, explicit `|| _ROOT=""`.
5. Regular-file check placed **after** the corpus notices, because the guard's
   corpus probe runs the engine against `/dev/null` — a character device.
6. Every new fixture must be shown to fail against the **real pre-fix code**,
   not merely against a mutation.

## Testing

Ten fixtures, all confirmed red against `origin/main` and green after:
`tests/test-publish-guard.sh` (53 assertions), `tests/test-memory-leak-check.sh`
(17). Mutation-proved: neutering the expansion case fails 4; dropping the corpus
`PIPESTATUS` guard fails 1; restoring the unguarded `_ROOT` fails 1.

Noted honestly: the S3 `PIPESTATUS` check alone tests as vacuous, because the
**non-truncation** is the load-bearing half of that fix. The status check is
defence-in-depth, and the fixture's real proof is that it fails against pre-fix
code.

**Test-shape lesson.** `assert_equals … "" "${out}"` for an "allowed" case
passes when the hook never ran, and therefore cannot distinguish "checked and
clean" from "never checked". That is why four contract violations shipped under
a green suite. New allow-path fixtures assert the **announcement**.
