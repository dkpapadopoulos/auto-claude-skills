# Proposal: the gitleaks step reports what gitleaks finds

## Why

Step 4 of `skills/security-scanner/SKILL.md` ran
`gitleaks detect --source . --no-banner --report-format json 2>/dev/null | jq …`.
gitleaks v8 writes its JSON report only to `--report-path`, never to stdout, so jq
got no input and printed nothing. Measured on gitleaks 8.30.1 with two planted AWS
keys in a scratch repo: the documented command printed nothing (gitleaks exit 1);
with `--report-path -` it printed both findings. A repo full of secrets read as
clean on every scan. The canonical scenario asked only for `--report-format json`,
which the broken command satisfied.

## What Changes

- The documented command writes the report to a temp file (`--report-path
  "$GL_REPORT"`) and runs jq on that file, then removes it. `--report-path -`
  means stdout only from gitleaks 8.22 (older releases write a file named `-`
  into the repo), and distributions still ship older v8 builds. `--redact` keeps
  secret values out of the session. gitleaks' stderr (counts, never secrets) is
  no longer discarded: `count: 0` is a pass only when it logged at least one
  commit scanned and no `ERR` line, because outside a usable repo gitleaks scans
  zero commits, exits 0 and writes `[]`. That scan covers committed history only;
  uncommitted work is scanned with `gitleaks protect --staged` and `gitleaks
  protect`, never by committing it first. `protect` always logs `0 commits
  scanned`, so its own pass rule is `count: 0` with no `ERR` line.
- `tests/test-security-scanner.sh` runs the command exactly as SKILL.md documents
  it against a scratch repo with a planted key, and asserts a non-zero count and
  that neither the key nor the secret value is in the parsed output. Seen red on
  the old command and on a mutant with the report path dropped. The fixture is
  built with the user's git and gitleaks config shut out (a global pre-commit
  hook made it fail falsely during review), and a fixture that cannot be built
  fails as such, never as a skill defect. Where gitleaks or jq is not installed
  the behavioural half is skipped; the flag assertions still run.

## Capabilities

- **Modified:** `security-scanner` (one requirement; the gitleaks scenario).

## Impact

- Users with gitleaks installed now see secret findings the step was dropping.
- `scripts/consult-dispatch.sh` already ran gitleaks correctly and is unchanged.
