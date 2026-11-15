# project-verification: verification receipt

## ADDED Requirements

### Requirement: A measured verdict can be rendered as a receipt bound to its commit

`scripts/verify-receipt.sh` MUST print a receipt on stdout and exit `0` only
when a verdict exists whose `writer` is `verify-and-record.sh`, whose
`discovery_source` is `verify-yml` or `explicit`, whose `sha` equals the current
`HEAD` exactly, and which was not measured on a dirty working tree. The receipt
MUST name the full commit sha, the time the verdict was recorded, every check
with its outcome, and the gate-gaming status, and MUST state that it was
produced on the author's machine and is not CI. Its first line MUST be the
marker `<!-- acs-verify-receipt v1 sha=<sha> result=<result> -->`.

A verdict with a failed or could-not-run check MUST still be rendered, with a
result of `fail` or `could-not-verify` and those checks named; a failing check
MUST NOT be omitted or summarised away.

In every other case the script MUST print nothing on stdout, MUST state the
reason on stderr, and MUST exit non-zero: `1` when there is no receipt to give,
`3` when it cannot check.

#### Scenario: A clean measured verdict at HEAD
- **GIVEN** `verify-and-record.sh` recorded a passing verdict for the current commit on a clean tree
- **WHEN** `verify-receipt.sh` runs in that repo
- **THEN** it exits `0` and stdout starts with the marker carrying that commit's full sha and `result=pass`
- **AND** each recorded check name appears with its outcome

#### Scenario: HEAD moved after verification
- **GIVEN** a measured verdict for a commit and one further commit on top of it
- **WHEN** `verify-receipt.sh` runs
- **THEN** stdout is empty, the exit status is `1`, and stderr names both the verified sha and the current sha

#### Scenario: A failing verdict is reported, not hidden
- **GIVEN** `verify-and-record.sh` recorded a verdict with one failed check for the current commit
- **WHEN** `verify-receipt.sh` runs
- **THEN** it exits `0`, the marker carries `result=fail`, and the failed check is named as failed

#### Scenario: A verdict measured on a dirty tree
- **GIVEN** a measured verdict for the current commit that records `worktree_dirty: true`
- **WHEN** `verify-receipt.sh` runs
- **THEN** stdout is empty, the exit status is `1`, and stderr says the verdict was measured with uncommitted changes

### Requirement: A receipt discloses outcomes only

A receipt MUST NOT contain the verdict's command lines, its output excerpt, its
dirty paths, the session token, or any path under the user's home directory.

#### Scenario: A credential in the gate command does not reach the receipt
- **GIVEN** a verdict recorded from an explicit command whose command line contains a distinctive secret-shaped string
- **WHEN** `verify-receipt.sh` renders the receipt
- **THEN** that string does not appear in the receipt
- **AND** neither does the text the command printed

### Requirement: The receipt is offered where the verdict is recorded

After `scripts/verify-and-record.sh` writes a measured verdict it MUST print the
exact command that renders the receipt, as an absolute single-quoted path. The
`project-verification` skill MUST instruct the agent to include the receipt
verbatim in the description of a pull request opened or updated for that commit,
and to render it again after any later commit. Neither MUST block a push or a
pull request when no receipt can be rendered.

#### Scenario: The writer names the receipt command
- **GIVEN** a repo with a declared or explicit gate
- **WHEN** `verify-and-record.sh` records a measured verdict
- **THEN** its output contains a line naming `verify-receipt.sh` by absolute path in single quotes

#### Scenario: No receipt, nothing blocked
- **GIVEN** a repo where no verdict has been recorded
- **WHEN** `verify-receipt.sh` runs
- **THEN** it exits `1` with a reason on stderr and performs no write and no network call
