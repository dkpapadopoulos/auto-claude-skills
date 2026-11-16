# project-verification: verification receipt

## ADDED Requirements

### Requirement: A measured verdict can be rendered as a receipt bound to its commit

`scripts/verify-receipt.sh` MUST print a receipt on stdout and exit `0` only
when a verdict exists whose `writer` is `verify-and-record.sh`, whose
`discovery_source` is `verify-yml` or `explicit`, whose `sha` equals the current
`HEAD` exactly, and which was not measured on a dirty working tree. The receipt
MUST name the full commit sha, the time the verdict was recorded, the outcome
of every check, and the gate-gaming status, and MUST state that it was
produced on the author's machine and is not CI. Its first line MUST be the
marker `<!-- acs-verify-receipt v1 sha=<sha> result=<result> -->`.

A verdict with a failed or could-not-run check MUST still be rendered, with a
result of `fail` or `could-not-verify`; a failing check MUST NOT be omitted. The
result MUST be `pass` only when no check failed, none could not run, at least
one passed, and the gate-gaming status is `clean`.

In every other case the script MUST print nothing on stdout, MUST state the
reason on stderr, and MUST exit non-zero: `1` when there is no receipt to give,
`3` when it cannot check.

#### Scenario: A clean measured verdict at HEAD
- **GIVEN** `verify-and-record.sh` recorded a passing verdict for the current commit on a clean tree
- **WHEN** `verify-receipt.sh` runs in that repo
- **THEN** it exits `0` and stdout starts with the marker carrying that commit's full sha and `result=pass`
- **AND** each recorded check with a plain-label name appears with its outcome

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
dirty paths, the session token, or any path under the user's home directory. A
check name MUST be printed only when it is a plain label (letters, digits, dot,
underscore, hyphen, space; at most 60 characters); a check with any other name
MUST be counted under its outcome and its name not printed.

#### Scenario: A check name that is not a plain label
- **GIVEN** a verdict with a passed check named `x --> @everyone`
- **WHEN** `verify-receipt.sh` renders the receipt
- **THEN** the name does not appear and one passed check is counted as having a name that is not a plain label

#### Scenario: A gate-gaming status that is not clean
- **GIVEN** a verdict with every check passed and a gate-gaming status of `unverified`
- **WHEN** `verify-receipt.sh` renders the receipt
- **THEN** the marker carries `result=could-not-verify`

#### Scenario: A credential in the gate command does not reach the receipt
- **GIVEN** a verdict recorded from an explicit command whose command line contains a distinctive secret-shaped string
- **WHEN** `verify-receipt.sh` renders the receipt
- **THEN** that string does not appear in the receipt
- **AND** neither does the text the command printed

### Requirement: The receipt is offered where the verdict is recorded

After `scripts/verify-and-record.sh` writes a measured verdict for which a
receipt can be rendered (the working tree was clean and `HEAD` did not move
during the run), it MUST print the exact command that renders the receipt, as
an absolute single-quoted path. For any other verdict it MUST NOT name the
command, because the command would refuse. The
`project-verification` skill MUST instruct the agent to include the receipt
verbatim in the description of a pull request opened or updated for that commit,
and to render it again after any later commit. Neither MUST block a push or a
pull request when no receipt can be rendered.

#### Scenario: The writer names the receipt command
- **GIVEN** a repo with a declared or explicit gate
- **WHEN** `verify-and-record.sh` records a measured verdict
- **THEN** its output contains a line naming `verify-receipt.sh` by absolute path in single quotes

#### Scenario: A dirty-tree verdict names no receipt command
- **GIVEN** a repo with uncommitted changes to a tracked file
- **WHEN** `verify-and-record.sh` records a measured verdict
- **THEN** its output does not name `verify-receipt.sh`

#### Scenario: No receipt, nothing blocked
- **GIVEN** a repo where no verdict has been recorded
- **WHEN** `verify-receipt.sh` runs
- **THEN** it exits `1` with a reason on stderr and performs no write and no network call
