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

- The documented command adds `--report-path -` (report on stdout) and `--redact`
  (secret values never enter the session), and a line under it says an empty
  result is not a pass.
- `tests/test-security-scanner.sh` runs the command exactly as SKILL.md documents
  it against a scratch repo with a planted key, and asserts a non-zero count and
  that the secret value is absent from the output. Seen red on the old command.
  Where gitleaks or jq is not installed the behavioural half is skipped; the
  flag assertions still run.

## Capabilities

- **Modified:** `security-scanner` (one requirement; the gitleaks scenario).

## Impact

- Users with gitleaks installed now see secret findings the step was dropping.
- `scripts/consult-dispatch.sh` already ran gitleaks correctly and is unchanged.
